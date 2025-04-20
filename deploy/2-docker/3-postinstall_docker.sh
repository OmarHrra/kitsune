#!/usr/bin/env bash
set -euo pipefail

# 3-postinstall_docker.sh
#
# Usage:
#   chmod +x 3-postinstall_docker.sh
#   ./3-postinstall_docker.sh --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback] [-h|--help]
#
# Required:
#   --server-ip      Server IP address or hostname
#
# Optional:
#   --ssh-port       SSH port (default: $SSH_PORT or 22)
#   --ssh-key-path   Path to your private SSH key (default: $SSH_KEY_PATH or ~/.ssh/id_rsa)
#   --rollback       Undo post-install Docker configuration
#
# Options:
#   -h, --help       Show this help and exit

print_usage() {
  cat <<EOF
Usage:
  $0 --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback] [-h|--help]

Required:
  --server-ip      Server IP address or hostname

Optional:
  --ssh-port       SSH port (default: \$SSH_PORT or 22)
  --ssh-key-path   Path to your private SSH key (default: \$SSH_KEY_PATH or ~/.ssh/id_rsa)
  --rollback       Undo Docker post-install steps

Options:
  -h, --help       Show this help and exit
EOF
}

# Load environment for defaults
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
    --server-ip)    SERVER_IP="$2";    shift 2;;
    --ssh-port)     SSH_PORT="$2";     shift 2;;
    --ssh-key-path) SSH_KEY_PATH="$2"; shift 2;;
    --rollback)     ROLLBACK=true;      shift;;
    -h|--help)      print_usage; exit 0;;
    *) echo "⚠️ Unknown parameter: $1" >&2; print_usage >&2; exit 1 ;;
  esac
done

# Validate
if [ -z "${SERVER_IP:-}" ]; then
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

# Backup identifiers
SCRIPT_ID="$(basename "$0" .sh)"
BACKUP_DIR="/usr/local/backups"
BEFORE_FILE="$BACKUP_DIR/${SCRIPT_ID}.before"
AFTER_FILE="$BACKUP_DIR/${SCRIPT_ID}.after"

# Prepare remote backup directory
REMOTE_PREPARE_DIR=$(cat <<'EOF'
sudo mkdir -p /usr/local/backups
sudo chown deploy:deploy /usr/local/backups
EOF
)

# Remote execution
ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<EOF
set -e
$REMOTE_PREPARE_DIR

echo "✍🏻 Performing post-install Docker tasks"

if [ "$ROLLBACK" = true ]; then
  echo "🔄 Rolling back post-install Docker tasks..."
  if [ -f "$AFTER_FILE" ]; then
    # Disable Docker service if enabled by this script
    if grep -Fxq "docker.service enabled" "$AFTER_FILE"; then
      sudo systemctl disable docker
      echo "   - Docker service disabled"
    fi
    # Remove deploy from docker group if added
    if grep -Fxq "added docker group" "$AFTER_FILE"; then
      sudo gpasswd -d deploy docker || true
      echo "   - Removed 'deploy' from docker group"
    fi
    # Remove private network if created
    if grep -Fxq "created network private" "$AFTER_FILE"; then
      sudo docker network rm private || true
      echo "   - Removed Docker network 'private'"
    fi
  else
    echo "   - no marker for $SCRIPT_ID, skipping rollback"
  fi
  # Cleanup markers
  sudo rm -f "$BEFORE_FILE" "$AFTER_FILE"
  echo "✅ Rollback complete"
  exit 0
fi

# Setup branch
if [ ! -f "$AFTER_FILE" ]; then
  # Record existing state
  systemctl is-enabled docker &>/dev/null && echo "docker.service enabled" >> "$BEFORE_FILE" || echo "docker.service disabled" >> "$BEFORE_FILE"
  groups deploy | grep -q docker && echo "deploy in docker group" >> "$BEFORE_FILE" || echo "deploy not in docker group" >> "$BEFORE_FILE"
  sudo docker network inspect private &>/dev/null && echo "network private exists" >> "$BEFORE_FILE" || echo "network private absent" >> "$BEFORE_FILE"

  # Start & enable Docker
  sudo systemctl start docker
  sudo systemctl enable docker
  echo "🚀 Docker service started and enabled"
  echo "docker.service enabled" >> "$AFTER_FILE"

  # Add deploy to docker group
  sudo usermod -aG docker deploy
  echo "👥 Added 'deploy' to docker group"
  echo "added docker group" >> "$AFTER_FILE"

  # Create private network if missing
  if ! sudo docker network inspect private &>/dev/null; then
    sudo docker network create -d bridge private
    echo "🌐 Created Docker network 'private'"
    echo "created network private" >> "$AFTER_FILE"
  fi

  echo "✅ Post-install Docker tasks complete"
else
  echo "🔄 Post-install tasks already applied, skipping setup"
fi
EOF
