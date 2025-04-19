#!/usr/bin/env bash
set -euo pipefail

# 4-setup_unattended.sh
#
# Usage:
#   chmod +x 4-setup_unattended.sh
#   ./4-setup_unattended.sh --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback] [-h|--help]
#
# Required:
#   --server-ip      IP address or hostname
#
# Optional:
#   --ssh-port       SSH port (default: $SSH_PORT or 22)
#   --ssh-key-path   SSH key path (default: $SSH_KEY_PATH or ~/.ssh/id_rsa)
#   --rollback       Revert unattended-upgrades configuration

print_usage() {
  cat <<EOF
Usage:
  $0 --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback] [-h|--help]

Required:
  --server-ip      Server IP address or hostname

Optional:
  --ssh-port       SSH port (default: \$SSH_PORT or 22)
  --ssh-key-path   SSH key path (default: \$SSH_KEY_PATH or ~/.ssh/id_rsa)
  --rollback       Perform rollback instead of setup

Options:
  -h, --help       Show this help and exit
EOF
}

# ————————— LOAD ENVIRONMENT —————————
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/load_env.sh"

# Defaults
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
ROLLBACK=false

# Parse flags
if [ $# -eq 0 ]; then
  print_usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-ip)    SERVER_IP="$2";      shift 2 ;;
    --ssh-port)     SSH_PORT="$2";       shift 2 ;;
    --ssh-key-path) SSH_KEY_PATH="$2";   shift 2 ;;
    --rollback)     ROLLBACK=true;       shift   ;;
    -h|--help)      print_usage; exit 0 ;;
    *) echo "⚠️ Unknown parameter: $1" >&2; print_usage >&2; exit 1 ;;
  esac
done

# Validate required
if [[ -z "${SERVER_IP:-}" ]]; then
  echo "❌ --server-ip is required" >&2
  exit 1
fi

# SSH options
SSH_OPTS=(
  -i "$SSH_KEY_PATH"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -p "$SSH_PORT"
)

# Unique identifier for backups/marker
SCRIPT_ID="$(basename "$0" .sh)"

# Paths for resource, backups and marker
RESOURCE="/etc/apt/apt.conf.d/20auto-upgrades"
BACKUP_DIR="/usr/local/backups"
BACKUP_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
MARKER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

# Ensure backup dir exists on remote
REMOTE_PREPARE_DIR=$(cat <<'EOF'
sudo mkdir -p /usr/local/backups
sudo chown deploy:deploy /usr/local/backups
EOF
)

# ———— ROLLBACK BRANCH ————
if [ "$ROLLBACK" = true ]; then
  echo "🔑 Connecting as deploy@$SERVER_IP for ROLLBACK"
  if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<EOF
set -e
$REMOTE_PREPARE_DIR

if [ -f "$MARKER_FILE" ]; then
  echo "✍🏻 Restoring original auto-upgrades config…"
  sudo mv "$BACKUP_FILE" "$RESOURCE" \
    && echo "   - config restored from $BACKUP_FILE"
  sudo rm -f "$MARKER_FILE" \
    && echo "   - marker $MARKER_FILE removed"
else
  echo "   - no marker for $SCRIPT_ID, skipping restore"
fi

echo "✍🏻 Stopping & disabling unattended-upgrades…"
sudo systemctl --quiet stop unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer \
  && echo "   - services stopped"
sudo systemctl --quiet disable unattended-upgrades.service \
  && echo "   - service disabled"

echo "✅ Unattended-upgrades rollback completed"
EOF
  then
    exit 0
  else
    echo "❌ Rollback failed" >&2
    exit 1
  fi
fi

# ———— SETUP BRANCH ————
echo "🔑 Connecting as deploy@$SERVER_IP for SETUP"
if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<EOF
set -e
$REMOTE_PREPARE_DIR

echo "✍🏻 Installing required packages…"
if ! dpkg -l | grep -q "^ii\s*unattended-upgrades"; then
  sudo apt-get update -y
  sudo apt-get install -y unattended-upgrades apt-listchanges \
    && echo "   - packages installed"
else
  echo "   - unattended-upgrades already installed"
fi

# Backup + marker only the first time
if [ ! -f "$MARKER_FILE" ]; then
  echo "✍🏻 Backing up existing config…"
  sudo cp "$RESOURCE" "$BACKUP_FILE" \
    && echo "   - backup saved to $BACKUP_FILE"
  sudo touch "$MARKER_FILE" \
    && echo "   - marker created at $MARKER_FILE"
else
  echo "   - backup & marker already exist"
fi

echo "✍🏻 Applying new auto-upgrades config…"
sudo tee "$RESOURCE" > /dev/null <<UPGR
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
UPGR
echo "   - config applied"

echo "✍🏻 Enabling & restarting unattended-upgrades…"
sudo systemctl --quiet enable unattended-upgrades.service >/dev/null 2>&1 \
  && echo "   - service enabled"
sudo systemctl --quiet restart unattended-upgrades.service \
  && echo "   - service restarted"

echo "✅ Automatic updates configured by $SCRIPT_ID"
EOF
then
  exit 0
else
  echo "❌ Setup failed" >&2
  exit 1
fi
