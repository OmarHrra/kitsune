#!/usr/bin/env bash
set -euo pipefail

# 4-setup_unattended.sh
#
# Usage:
#   chmod +x 4-setup_unattended.sh
#   ./4-setup_unattended.sh --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback]
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
  $0 --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback]

Required:
  --server-ip      Server IP address or hostname

Optional:
  --ssh-port       SSH port (default: \$SSH_PORT or 22)
  --ssh-key-path   Path to your private SSH key (default: \$SSH_KEY_PATH or ~/.ssh/id_rsa)
  --rollback       Revert unattended-upgrades configuration

Examples:
  $0 --server-ip 1.2.3.4
  $0 --server-ip 1.2.3.4 --ssh-port 2222
  $0 --server-ip 1.2.3.4 --ssh-key-path ~/.ssh/id_rsa
  $0 --server-ip 1.2.3.4 --rollback
EOF
}

# ————————— LOAD ENVIRONMENT —————————
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/load_env.sh"

# Defaults
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
ROLLBACK=false

# ————————— PARSE FLAGS —————————
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
    *) echo "⚠️  Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
  esac
done

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

# ———— ROLLBACK BRANCH ————
if [ "$ROLLBACK" = true ]; then
  echo "🔑 Connecting as deploy@$SERVER_IP for ROLLBACK"
  if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<'EOF'
    set -e

    echo "⟳ Reverting auto-upgrades config…"
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades.bak ]; then
      sudo mv /etc/apt/apt.conf.d/20auto-upgrades.bak /etc/apt/apt.conf.d/20auto-upgrades \
        && echo "   - original config restored"
    else
      echo "   - no config backup to restore"
    fi

    echo "⟳ Stopping timers and service…"
    sudo systemctl stop apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service \
      && echo "   - timers and service stopped"
    sudo systemctl disable unattended-upgrades.service \
      >/dev/null 2>&1 && echo "   - service disabled"

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
if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<'EOF'
  set -e

  echo "⟳ Installing required packages…"
  if ! dpkg -l | grep -q "^ii  unattended-upgrades "; then
    sudo apt-get update -y
    sudo apt-get install -y unattended-upgrades apt-listchanges && echo "   - packages installed"
  else
    echo "   - packages already installed"
  fi

  echo "⟳ Backing up existing auto-upgrades config…"
  if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && [ ! -f /etc/apt/apt.conf.d/20auto-upgrades.bak ]; then
    sudo cp /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades.bak \
      && echo "   - original config backed up"
  else
    echo "   - backup already exists or no original config"
  fi

  echo "⟳ Deploying auto-upgrades config…"
  sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<UPGR
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
UPGR
  echo "   - config applied"

  echo "⟳ Enabling & restarting unattended-upgrades service…"
  sudo systemctl enable unattended-upgrades.service >/dev/null 2>&1 && echo "   - service enabled"
  sudo systemctl restart unattended-upgrades.service && echo "   - service started"

  echo "✅ Automatic updates configured"
EOF
then
  exit 0
else
  echo "❌ Setup failed" >&2
  exit 1
fi
