#!/usr/bin/env bash
set -euo pipefail

# 1-setup_docker_prereqs.sh
#
# Usage:
#   chmod +x 1-setup_docker_prereqs.sh
#   ./1-setup_docker_prereqs.sh --server-ip IP [--ssh-port PORT] [--rollback] [-h|--help]
#
# Required:
#   --server-ip      Server IP address or hostname
#
# Optional:
#   --ssh-port       SSH port (default: $SSH_PORT or 22)
#   --rollback       Remove packages installed by this script
#
# Options:
#   -h, --help       Show this help and exit

print_usage() {
  cat <<EOF
Usage:
  $0 --server-ip IP [--ssh-port PORT] [--rollback] [-h|--help]

Required:
  --server-ip      Server IP address or hostname

Optional:
  --ssh-port       SSH port (default: \$SSH_PORT or 22)
  --rollback       Remove packages installed by this script

Options:
  -h, --help       Show this help and exit
EOF
}

# Load environment (for default SSH_PORT if set)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/load_env.sh"

# Defaults
SSH_PORT="${SSH_PORT:-22}"
ROLLBACK=false

# Parse flags
if [ $# -eq 0 ]; then
  print_usage
  exit 1
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-ip)    SERVER_IP="$2";    shift 2 ;;  
    --ssh-port)     SSH_PORT="$2";     shift 2 ;;  
    --rollback)     ROLLBACK=true;     shift   ;;  
    -h|--help)      print_usage; exit 0 ;;  
    *) echo "⚠️ Unknown parameter: $1" >&2; print_usage >&2; exit 1 ;;  
  esac
done

# Validate
if [ -z "$SERVER_IP" ]; then
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

# Unique ID for backups/marker
SCRIPT_ID="$(basename "$0" .sh)"

# Backup directory and files on remote
BACKUP_DIR="/usr/local/backups"
BEFORE_FILE="${BACKUP_DIR}/${SCRIPT_ID}.before"
AFTER_FILE="${BACKUP_DIR}/${SCRIPT_ID}.after"

# Remote setup of backup dir
REMOTE_PREPARE_DIR=$(cat <<'EOF'
sudo mkdir -p /usr/local/backups
sudo chown deploy:deploy /usr/local/backups
EOF
)

# Execute on remote
if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<EOF
set -e
$REMOTE_PREPARE_DIR

# Packages to install/remove
TARGET_PKGS=(
  apt-transport-https
  ca-certificates
  curl
  gnupg
  lsb-release
  software-properties-common
)

echo "✍🏻 TARGET_PKGS=(\${TARGET_PKGS[*]})"

if [ "$ROLLBACK" = true ]; then
  echo "🔄 Rolling back docker prerequisites setup..."
  if [ -f "$AFTER_FILE" ]; then
    # Identify packages to remove (those not present before)
    to_remove=()
    for pkg in "\${TARGET_PKGS[@]}"; do
      if dpkg -l "\$pkg" &>/dev/null; then
        if ! grep -Fxq "\$pkg" "$BEFORE_FILE"; then
          to_remove+=("\$pkg")
        fi
      fi
    done
    if [ \${#to_remove[@]} -gt 0 ]; then
      sudo apt-get remove -y "\${to_remove[@]}" && echo "   - removed: \${to_remove[*]}"
    else
      echo "   - no new packages to remove"
    fi
    sudo rm -f "$BEFORE_FILE" "$AFTER_FILE" && echo "   - backups removed"
  else
    echo "   - no marker for $SCRIPT_ID, skipping removal"
  fi
  echo "✅ Rollback completed"
  exit 0
fi

# Setup branch
if [ ! -f "$AFTER_FILE" ]; then
  # Record which packages were already installed
  for pkg in "\${TARGET_PKGS[@]}"; do
    if dpkg -l "\$pkg" &>/dev/null; then
      echo "\$pkg" >> "$BEFORE_FILE"
    fi
  done
  # Install prerequisites
  echo "✍🏻 Installing prerequisites..."
  sudo apt-get update -y
  sudo apt-get install -y "\${TARGET_PKGS[@]}"
  sudo touch "$AFTER_FILE" && echo "   - marker created at $AFTER_FILE"
  echo "✅ Prerequisites installed"
else
  sudo apt-get update -y
  sudo apt-get install -y "\${TARGET_PKGS[@]}"
  echo "✅ Prerequisites are current"
fi
EOF
then
  exit 0
else
  echo "❌ Remote execution failed" >&2
  exit 1
fi
