# Docker Compose: patterns + hardening baseline

Concrete compose YAML for running a hardened container stack. For the
principles behind these settings (least privilege, image hygiene, secrets,
resource limits), see [container-security-guide.md](container-security-guide.md);
to check a running host against them, use
[docker-container-audit.sh](../scripts/docker-container-audit.sh).

## A hardening baseline with YAML anchors

Define once, merge into every service:

```yaml
x-hardening: &hardening
  security_opt:
    - no-new-privileges:true
  restart: unless-stopped
  logging:
    driver: json-file
    options: { max-size: "10m", max-file: "5" }

services:
  app:
    <<: *hardening
    image: example/app:1.2.3          # pin a tag (or a digest); avoid :latest in prod
    mem_limit: 512m
    pids_limit: 512
    read_only: true                   # if the app tolerates it
    tmpfs: [/tmp]
    cap_drop: [ALL]
    cap_add: [CHOWN, SETUID, SETGID]  # add back only what breaks without it
    environment:
      - TZ=UTC
    env_file: [./app.env]             # secrets here; app.env is .gitignore'd
    ports:
      - "127.0.0.1:8080:8080"         # bind to loopback unless it must face the LAN
```

Also set daemon-wide in `/etc/docker/daemon.json`:
```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "live-restore": true,
  "no-new-privileges": true
}
```
`systemctl restart docker` (with `live-restore` the containers survive it).

## Secrets

- Never put a real value in a compose file. Use `${VAR}` (from a `.env` beside
  the compose file, which is `.gitignore`'d) or `env_file:` or Docker/Swarm
  secrets or a `_FILE` env var (`FOO_FILE=/run/secrets/foo`).
- Grep your history before making a repo public:
  `git log --all -p | grep -nEi 'api[_-]?key|secret|token|password'`

## Networking

- One user network per stack; only expose ports that truly need host access.
- Loopback-bind (`127.0.0.1:`) anything that sits behind a reverse proxy.
- Read-only docker.sock for things that only need to *watch* (dashboards,
  autoheal): `-v /var/run/docker.sock:/var/run/docker.sock:ro`, or better a
  socket-proxy that filters the API.

## Healthchecks (so `restart:` actually helps)

```yaml
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
```

## Init / PID 1

Add `init: true` for apps that fork and don't reap children. Do **not** add it
to images that already ship their own init (s6-overlay, tini, supervisor) —
you'll get `pid 1` conflicts and crash loops.

## Operational one-liners

```bash
docker compose config -q                       # validate before deploy
docker compose up -d --remove-orphans
docker ps --filter health=unhealthy
docker inspect --format '{{.Name}} {{.RestartCount}}' $(docker ps -q) | sort -k2 -n
docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}'
docker system df ; docker system prune        # reclaim (add --volumes carefully)
```

## Keep the stack in git

Compose files, non-secret config, and provisioning scripts belong in version
control; data dirs and `.env` do not. A diffable history of every stack change
is worth more than most people expect the first time they need to roll one back.
