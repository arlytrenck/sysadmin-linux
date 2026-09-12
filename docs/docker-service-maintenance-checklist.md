# Docker Service Stack Maintenance Checklist

A structured checklist for maintaining Docker-based service stacks to ensure reliability, security, and data integrity.

## Health & Status

- [ ] Verify all containers are running (`docker compose ps`)
- [ ] Check container health status (`docker compose ps` shows 'healthy')
- [ ] Review container logs for recurring errors/warnings (`docker compose logs --tail=100`)
- [ ] Verify no containers are stuck in a restart loop

## Backups & Data

- [ ] Confirm automated database dumps have run successfully
- [ ] Verify off-site backup integrity (recent logs, checksums)
- [ ] Ensure persistent volumes have sufficient space
- [ ] Test a restoration of a non-critical volume to verify backup usability

## Updates & Security

- [ ] Check for available image updates (`docker compose pull` dry-run)
- [ ] Review container resource usage (CPU/Memory leaks)
- [ ] Prune unused images and build caches (`docker system prune`)
- [ ] Scan for known vulnerabilities in running images (if applicable)

## Configuration

- [ ] Verify environment variables/secrets remain consistent
- [ ] Review `docker-compose.yml` for drift against best practices (e.g., unnecessary privileged mode)
- [ ] Check bind mounts for risky host paths (`/etc`, `docker.sock`)

## Post-Maintenance

- [ ] Confirm service responsiveness after any restarts
- [ ] Update documentation if configuration changes were made
- [ ] Clear any temporary logs or artifacts created during maintenance
