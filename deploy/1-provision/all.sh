#!/usr/bin/env bash
set -euo pipefail

# all.sh
#
# Usage:
#   chmod +x all.sh
#   sh all.sh [--rollback] [--keep-server] [--ssh-port PORT] [--ssh-key-path PATH] [-h | --help]
#
# Default (no flags): Creates droplet, configures user, firewall, unattended upgrades.
# --rollback: Reverts user, firewall, unattended upgrades, then deletes droplet.
# --keep-server: When used with --rollback, skips droplet deletion.
# --ssh-port: SSH port for scripts 2-4 (default: $SSH_PORT or 22)
# --ssh-key-path: Path to SSH private key for scripts 2-4 (default: $SSH_KEY_PATH or ~/.ssh/id_rsa)
# -h, --help: Show this help message and exit.

print_usage() {
  cat <<EOF
Usage: sh $0 [--rollback] [--keep-server] [--ssh-port PORT] [--ssh-key-path PATH] [-h | --help]

Options:
  --rollback       Revert user, firewall, unattended upgrades, then delete droplet.
  --keep-server    When used with --rollback, skips droplet deletion.
  --ssh-port       SSH port for scripts 2-4 (default: \$SSH_PORT or 22).
  --ssh-key-path   Path to your private SSH key for scripts 2-4 (default: \$SSH_KEY_PATH or ~/.ssh/id_rsa).
  -h, --help       Show this help message and exit.
EOF
  exit 0
}

# ————————— LOAD ENVIRONMENT —————————
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/load_env.sh"

# Script paths
SCRIPT_CREATE="$SCRIPT_DIR/1-create_droplet.sh"
SCRIPT_USER="$SCRIPT_DIR/2-setup_user.sh"
SCRIPT_FW="$SCRIPT_DIR/3-setup_firewall.sh"
SCRIPT_UNATT="$SCRIPT_DIR/4-setup_unattended.sh"

# Defaults for optional flags
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
ROLLBACK=false
KEEP_SERVER=false

# ————————— PARSE FLAGS —————————
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      ;;
    --rollback)
      ROLLBACK=true; shift
      ;;
    --keep-server)
      KEEP_SERVER=true; shift
      ;;
    --ssh-port)
      SSH_PORT="$2"; shift 2
      ;;
    --ssh-key-path)
      SSH_KEY_PATH="$2"; shift 2
      ;;
    --*)
      echo "⚠️ Unknown option: $1" >&2; print_usage
      ;;
    *)
      break
      ;;
  esac
done

# Function to fetch existing droplet IP without deletion
fetch_droplet_ip() {
  local info ip
  info="$(bash "$SCRIPT_CREATE")"
  # Extract the first occurrence of an IPv4 address
  ip=$(echo "$info" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
  echo "$ip"
}

# MAIN LOGIC
if [ "$ROLLBACK" = false ]; then
  echo "🏗️  Creating or showing droplet..."
  DROPLET_IP=$(fetch_droplet_ip)
  echo "→ Droplet IP: $DROPLET_IP"

  echo "👤  Configuring user..."
  bash "$SCRIPT_USER" --server-ip "$DROPLET_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH"

  echo "🛡️  Setting up firewall..."
  bash "$SCRIPT_FW" --server-ip "$DROPLET_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH"

  echo "🔄  Configuring unattended upgrades..."
  bash "$SCRIPT_UNATT" --server-ip "$DROPLET_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH"
else
  echo "🔄  Rolling back configurations..."
  DROPLET_IP=$(fetch_droplet_ip)
  echo "→ Using Droplet IP: $DROPLET_IP"

  echo "🔄  Rolling back unattended upgrades..."
  # Skip if deploy user missing
  if ssh -o BatchMode=yes deploy@"$DROPLET_IP" true 2>/dev/null; then
    bash "$SCRIPT_UNATT" --server-ip "$DROPLET_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH" --rollback
  else
    echo "⏭️  Skipping unattended-upgrades rollback: deploy user missing"
  fi

  echo "🛡️  Rolling back firewall rules..."
  # Skip if deploy user missing
  if ssh -o BatchMode=yes deploy@"$DROPLET_IP" true 2>/dev/null; then
    bash "$SCRIPT_FW" --server-ip "$DROPLET_IP" --ssh-port "$SSH_PORT" --ssh-key-path="$SSH_KEY_PATH" --rollback
  else
    echo "⏭️  Skipping firewall rollback: deploy user missing"
  fi

  echo "👤  Rolling back user changes..."
  bash "$SCRIPT_USER" --server-ip "$DROPLET_IP" --ssh-port "$SSH_PORT" --ssh-key-path="$SSH_KEY_PATH" --rollback

  if [ "$KEEP_SERVER" = false ]; then
    echo "💥  Deleting droplet..."
    bash "$SCRIPT_CREATE" --rollback
  else
    echo "⏭️  Skipping droplet deletion (--keep-server enabled)"
  fi
fi

echo "🎉 Done!"
