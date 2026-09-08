# Resource library

Use these maintained references to validate commands and deepen the runbooks in this repository. Prefer primary documentation for current behavior, package syntax, and security guidance.

## Core Linux administration

- [systemd manual pages](https://www.freedesktop.org/software/systemd/man/latest/). Units, journald, timers, resource controls, and service sandboxing.
- [GNU Bash manual](https://www.gnu.org/software/bash/manual/). Shell syntax and safe scripting behavior.
- [OpenSSH manual pages](https://www.openssh.com/manual.html). SSH client/server configuration and key management.
- [Linux kernel documentation](https://docs.kernel.org/). Kernel parameters, filesystems, networking, and pressure metrics.

## Networking and security

- [nftables wiki](https://wiki.nftables.org/wiki-nftables/index.php/Main_Page). Current firewall concepts and rule syntax.
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks). Platform-specific security baselines.
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html). Storing and rotating credentials safely.
- [CISA Secure by Design](https://www.cisa.gov/securebydesign). Risk-reduction principles useful when evaluating software and operations.

## Containers, backups, and observability

- [Docker documentation](https://docs.docker.com/). Engine, Compose, networking, and security reference.
- [Prometheus documentation](https://prometheus.io/docs/introduction/overview/). Metrics and alerting fundamentals.
- [Restic documentation](https://restic.readthedocs.io/en/stable/). Encrypted backups, retention, integrity checks, and restores.
- [Tailscale knowledge base](https://tailscale.com/kb). Mesh VPN, ACLs, routing, and DNS.

## Practical use

Use the repository scripts and runbooks as a reviewable starting point, then compare any command against the installed version's man page or vendor documentation. Test changes in a disposable VM or maintenance window, retain a rollback path, and record what you actually changed.
