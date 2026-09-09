#!/usr/bin/env bash
#
# user-mgmt.sh — small helper for common local user administration tasks:
# create a user with an SSH key, lock a user, or remove a user.
#
# Usage:
#   ./user-mgmt.sh create -u <username> [-k /path/to/pubkey] [-s /bin/bash] [--sudo]
#   ./user-mgmt.sh lock   -u <username>
#   ./user-mgmt.sh unlock -u <username>
#   ./user-mgmt.sh remove -u <username> [--purge-home]
#
# "lock" disables the password, expires the account, and moves authorized_keys
# aside. All three are needed: usermod -L alone leaves SSH key login working,
# so a locked-looking account can still be used. Running sessions are reported
# but not killed.
#
# Must be run as root (or via sudo). This script only wraps standard
# useradd/usermod/userdel calls — review before running in production.

set -euo pipefail

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: this script must be run as root" >&2
    exit 1
  fi
}

usage() { sed -n '2,/^[^#]/p' "$0" | sed '1{/^#$/d;}; $d; s/^# \{0,1\}//'; exit "${1:-0}"; }

[[ $# -ge 1 ]] || usage 1
# "-h" on its own was being taken as the subcommand, so it printed a spurious
# "-u is required" error and exited 1 before reaching the -h case below.
case "${1:-}" in -h|--help) usage 0 ;; esac
CMD="$1"; shift

USERNAME=""
PUBKEY=""
SHELL_PATH="/bin/bash"
GRANT_SUDO=0
PURGE_HOME=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) USERNAME="$2"; shift 2 ;;
    -k) PUBKEY="$2"; shift 2 ;;
    -s) SHELL_PATH="$2"; shift 2 ;;
    --sudo) GRANT_SUDO=1; shift ;;
    --purge-home) PURGE_HOME=1; shift ;;
    -h) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$USERNAME" ]] || { echo "Error: -u <username> is required" >&2; usage 1; }

case "$CMD" in
  create)
    require_root
    if id "$USERNAME" &>/dev/null; then
      echo "Error: user '$USERNAME' already exists" >&2
      exit 1
    fi
    useradd -m -s "$SHELL_PATH" "$USERNAME"
    echo "Created user '$USERNAME' (shell: $SHELL_PATH)"

    if [[ -n "$PUBKEY" ]]; then
      # Without this, any file at all gets appended to authorized_keys: a
      # private key, a cert, a text file. ssh-keygen -l is the cheap check
      # that it really is a public key before it grants access.
      if [[ ! -r "$PUBKEY" ]]; then
        echo "Error: public key file '$PUBKEY' is not readable" >&2
        exit 1
      fi
      if ! ssh-keygen -l -f "$PUBKEY" >/dev/null 2>&1; then
        echo "Error: '$PUBKEY' is not a valid SSH public key file" >&2
        exit 1
      fi
      if grep -qi 'PRIVATE KEY' "$PUBKEY"; then
        echo "Error: '$PUBKEY' looks like a PRIVATE key. Refusing." >&2
        exit 1
      fi

      HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
      SSH_DIR="$HOME_DIR/.ssh"
      mkdir -p "$SSH_DIR"
      # Leading newline so the key cannot be glued onto a previous entry that
      # was written without a trailing one.
      printf '\n%s\n' "$(cat "$PUBKEY")" >> "$SSH_DIR/authorized_keys"
      chmod 700 "$SSH_DIR"
      chmod 600 "$SSH_DIR/authorized_keys"
      chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
      echo "Installed SSH public key for '$USERNAME' ($(ssh-keygen -l -f "$PUBKEY" | awk '{print $1" "$4}'))"
    fi

    if [[ "$GRANT_SUDO" -eq 1 ]]; then
      usermod -aG sudo "$USERNAME" 2>/dev/null || usermod -aG wheel "$USERNAME"
      echo "Granted sudo/wheel group membership to '$USERNAME'"
    fi
    ;;

  lock)
    require_root
    # usermod -L only disables the PASSWORD. A user with an authorized_keys
    # entry still logs in over SSH exactly as before, which makes "Locked
    # user" a dangerous thing to print during an offboarding. Expiring the
    # account is what actually stops both paths.
    usermod -L "$USERNAME"
    usermod -e 1 "$USERNAME"

    HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
    AK="$HOME_DIR/.ssh/authorized_keys"
    if [[ -s "$AK" ]]; then
      KEY_COUNT="$(grep -cvE '^[[:space:]]*(#|$)' "$AK" || true)"
      PARKED="$AK.locked-$(date +%Y%m%d-%H%M%S)"
      mv "$AK" "$PARKED"
      echo "Moved $KEY_COUNT key line(s) from $AK to $PARKED"
    fi

    if pgrep -u "$USERNAME" >/dev/null 2>&1; then
      echo "Note: '$USERNAME' still has running processes; existing sessions are not killed." >&2
    fi
    echo "Locked user '$USERNAME' (password disabled, account expired, SSH keys moved aside)"
    ;;

  unlock)
    require_root
    usermod -U "$USERNAME"
    usermod -e '' "$USERNAME"
    HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
    LATEST_AK="$(find "$HOME_DIR/.ssh" -maxdepth 1 -name 'authorized_keys.locked-*' 2>/dev/null | sort | tail -1)"
    if [[ -n "$LATEST_AK" ]]; then
      echo "Note: SSH keys are still parked at $LATEST_AK." >&2
      echo "      Restore them yourself once you are sure the account should have them." >&2
    fi
    echo "Unlocked user '$USERNAME' (password re-enabled, expiry cleared)"
    ;;

  remove)
    require_root
    if [[ "$PURGE_HOME" -eq 1 ]]; then
      userdel -r "$USERNAME"
      echo "Removed user '$USERNAME' and home directory"
    else
      userdel "$USERNAME"
      echo "Removed user '$USERNAME' (home directory retained)"
    fi
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    usage 1
    ;;
esac
