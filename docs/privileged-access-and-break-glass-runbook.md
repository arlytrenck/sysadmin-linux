# Privileged access and break-glass runbook

Use this runbook when ordinary administrative access is unavailable or when you need to perform a sensitive recovery action. It is intentionally conservative: restoring access must not quietly weaken the host's long-term security posture.

## Before declaring an emergency

Confirm the failure mode first. Test the expected hostname and route, then try a known-good SSH key from a trusted workstation. Check the out-of-band console or hypervisor view if available. A DNS, VPN, firewall, account, and host failure can look identical from a laptop.

Do not add a second emergency account or relax the firewall until you know which layer failed. Preserve timestamps, error messages, and the last known good change; they become the incident timeline.

## Authorized break-glass material

Keep a documented, reviewed path to each of these assets:

- A hardware-console, hypervisor-console, or provider-console method that does not depend on the host network.
- One named emergency administrator account with a unique SSH key or long random password stored in a password manager.
- The current host inventory, network addressing, and the normal administrative public keys.
- A current configuration snapshot and backup location.

The emergency account should be disabled or constrained whenever normal access works. Its use must generate an audit event and trigger review. Never share one generic root password among people.

## Recovery flow

1. Use the console path and identify the host. Record the system time, uptime, disk pressure, and recent boot history.
2. Check network basics locally: interface state, address, route, resolver, firewall, and SSH listener. Avoid restarting several services at once.
3. If the account/key path is broken, add the minimum required authorized key to the intended admin account with owner-only permissions. Prefer restoring the known key over inventing a permanent new account.
4. If privilege escalation is broken, repair the specific sudoers file with visudo validation. Do not broadly grant passwordless sudo to a recovery account as a shortcut.
5. Test a new SSH session before ending the console session. Confirm both normal login and sudo work.
6. Remove temporary keys, firewall rules, files, and console grants immediately after verification.

## Common failure modes

### SSH rejects the key

Check account ownership and permissions on the home directory, .ssh directory, and authorized_keys. Review sshd logs for the exact rejection reason, and verify the key algorithm is allowed by the active sshd configuration. Fix only the affected account first.

### Host is reachable but SSH is not

Confirm that sshd is active and listening on the intended address and port. Compare the effective configuration with the tracked baseline, then check a recent package upgrade, firewall change, or port conflict. Restarting sshd is reasonable only after validating the configuration.

### Disk full or filesystem read-only

Do not delete logs blindly. Identify the full filesystem, preserve the largest relevant log or crash evidence, rotate/truncate only a safe, understood file, and repair the cause. A read-only root filesystem may indicate storage failure; take a snapshot or copy evidence before a reboot.

### Sudo fails

Use the console as a trusted recovery path. Validate the smallest correction with visudo, check group membership and NSS/LDAP dependencies, then log out and back in before declaring success.

## After recovery

Create a short incident record: trigger, impact, evidence, access path used, exact changes, validation, and prevention work. Rotate any emergency credential that was exposed to a human or copied to a console. If the same class of failure can recur, automate a preflight check or add it to configuration management.

## Routine test

Test this process at least twice a year on a low-risk host or disposable VM. Verify that the emergency material is current, the console access still works, and the cleanup steps truly restore the hardened baseline. A break-glass process that has never been exercised is documentation, not recovery capability.
