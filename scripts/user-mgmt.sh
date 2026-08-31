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
# Must be run as root (or via sudo). This script only wraps standard
# useradd/usermod/userdel calls — review before running in production.

set -euo pipefail

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: this script must be run as root" >&2
    exit 1
  fi
}

usage() {
  grep '^#' "$0" | sed -n '2,10p' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

[[ $# -ge 1 ]] || usage 1
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
      HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
      SSH_DIR="$HOME_DIR/.ssh"
      mkdir -p "$SSH_DIR"
      cat "$PUBKEY" >> "$SSH_DIR/authorized_keys"
      chmod 700 "$SSH_DIR"
      chmod 600 "$SSH_DIR/authorized_keys"
      chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
      echo "Installed SSH public key for '$USERNAME'"
    fi

    if [[ "$GRANT_SUDO" -eq 1 ]]; then
      usermod -aG sudo "$USERNAME" 2>/dev/null || usermod -aG wheel "$USERNAME"
      echo "Granted sudo/wheel group membership to '$USERNAME'"
    fi
    ;;

  lock)
    require_root
    usermod -L "$USERNAME"
    echo "Locked user '$USERNAME'"
    ;;

  unlock)
    require_root
    usermod -U "$USERNAME"
    echo "Unlocked user '$USERNAME'"
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
