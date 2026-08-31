# Container Security Guide

A baseline for running Docker containers on a general-purpose Linux server
that isn't primarily a container host — the common case for a homelab or
small fleet that runs a handful of containerized services alongside
regular system services. Pairs with
[docker-container-audit.sh](../scripts/docker-container-audit.sh), which
checks a running host against several of the points below.

## Least privilege

- **Don't run as root inside the container.** Set a `USER` in the
  Dockerfile, or pass `--user`. Root inside a container is still root if
  a container-escape vulnerability is ever exploited.
- **Avoid `--privileged`.** It disables most of the isolation containers
  provide. If a workload genuinely needs a specific capability, add just
  that one with `--cap-add` instead of reaching for `--privileged`.
- **Mount volumes read-only where the container doesn't need to write**
  (`-v /host/path:/container/path:ro`). Config and code directories
  rarely need write access at runtime.
- **Don't bind-mount the Docker socket** (`/var/run/docker.sock`) into a
  container unless that container's entire purpose is to manage other
  containers (e.g. a CI runner or a monitoring agent) — socket access is
  equivalent to root on the host.

## Image hygiene

- **Pin image tags**, don't run `:latest` in anything you expect to be
  reproducible or auditable — you can't tell what you're running six
  months later.
- **Scan images for known CVEs** before deploying (`docker scout`,
  `trivy`, or your registry's built-in scanner) and again periodically,
  since new CVEs are found in existing images regularly.
- **Prefer minimal base images** (`-slim`, `-alpine`, distroless) —
  fewer packages means a smaller vulnerable surface and faster patching.
- **Rebuild on a schedule**, not just when the application changes — a
  base image that hasn't been rebuilt in months is carrying unpatched OS
  packages even if your own code hasn't changed.

## Secrets

- **Never bake secrets into an image layer** (`ENV`, `ARG`, or a
  `COPY`'d file) — they persist in image history even if a later layer
  deletes the file, and anyone who can pull the image can extract them.
- **Use `docker secret` (Swarm), a bind-mounted file with tight
  permissions, or an env var injected at container start** rather than
  a Dockerfile `ENV`.
- **Rotate anything that was ever exposed** the same as you would for a
  credential leaked any other way — treat "was in an image layer" as
  "was leaked."

## Resource limits

- **Set a memory limit on every long-running container** (`--memory` /
  `mem_limit` in compose) — an unbounded container with a leak can
  starve the whole host, taking down unrelated services.
- **Set a CPU limit or share** on anything that shouldn't be able to
  monopolize the host under load (`--cpus`, `--cpu-shares`).
- **Watch restart counts.** A container stuck in a restart loop is
  usually crash-looping on a bad config or a dependency it can't reach —
  `docker-container-audit.sh` flags this, but it's worth alerting on
  directly if you have a monitoring stack (see
  [monitoring-alerting-guide.md](monitoring-alerting-guide.md)).

## Networking

- **Don't publish ports to `0.0.0.0` unless the service genuinely needs
  to be reachable from outside the host.** Bind to `127.0.0.1:PORT:PORT`
  for anything only meant to be reached via a reverse proxy on the same
  host, or use a user-defined bridge network and let only the reverse
  proxy container publish a port.
- **Put unrelated containers on separate networks** rather than the
  default bridge, so a compromised container can't freely reach
  everything else running on the host.

## Updates

- **Patch the host and the Docker Engine itself**, not just the
  containers — a container security posture is only as good as the
  kernel and runtime underneath it. `update-and-patch.sh` covers the
  host side.
- **Track upstream security advisories** for any base images or
  third-party containers you run — a compromised or vulnerable upstream
  image is a supply-chain risk like any other dependency.
