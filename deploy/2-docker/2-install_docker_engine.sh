#!/usr/bin/env bash
set -euo pipefail

# 2-install_docker_engine.sh
#
# Usage:
#   chmod +x 2-install_docker_engine.sh
#   ./2-install_docker_engine.sh --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback] [-h|--help]
#
# Required:
#   --server-ip      Server IP address or hostname
#
# Optional:
#   --ssh-port       SSH port (default: $SSH_PORT or 22)
#   --ssh-key-path   Path to your private SSH key (default: $SSH_KEY_PATH or ~/.ssh/id_rsa)
#   --rollback       Remove Docker packages installed by this script
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
  --rollback       Remove Docker packages installed by this script

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
    --rollback)     ROLLBACK=true;     shift;;
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

# Unique ID for backups/marker
SCRIPT_ID="$(basename "$0" .sh)"
BACKUP_DIR="/usr/local/backups"
BEFORE_FILE="$BACKUP_DIR/${SCRIPT_ID}.before"
AFTER_FILE="$BACKUP_DIR/${SCRIPT_ID}.after"

# Remote prepare backup dir
REMOTE_PREPARE_DIR=$(cat <<'EOF'
sudo mkdir -p /usr/local/backups
sudo chown deploy:deploy /usr/local/backups
EOF
)

# Execute on remote
if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<EOF
set -e
$REMOTE_PREPARE_DIR

# Packages to manage
TARGET_PKGS=(docker-ce docker-ce-cli containerd.io)

echo "✍🏻 TARGET_PKGS=(\${TARGET_PKGS[*]})"

if [ "$ROLLBACK" = true ]; then
  echo "🔄 Rolling back Docker Engine installation..."
  if [ -f "$AFTER_FILE" ]; then
    to_remove=()
    for pkg in "\${TARGET_PKGS[@]}"; do
      if dpkg -l "\$pkg" &>/dev/null && ! grep -Fxq "\$pkg" "$BEFORE_FILE"; then
        to_remove+=("\$pkg")
      fi
    done
    if [ \${#to_remove[@]} -gt 0 ]; then
      sudo apt-get remove -y "\${to_remove[@]}" && echo "   - removed: \${to_remove[*]}"
    else
      echo "   - no Docker packages to remove"
    fi
    sudo rm -f "$BEFORE_FILE" "$AFTER_FILE" && echo "   - cleanup markers"
  else
    echo "   - no marker for $SCRIPT_ID, skipping"
  fi
  echo "✅ Rollback done"
  exit 0
fi

# Setup branch
if [ ! -f "$AFTER_FILE" ]; then
  # Record existing installs
  for pkg in "\${TARGET_PKGS[@]}"; do
    if dpkg -l "\$pkg" &>/dev/null; then
      echo "\$pkg" >> "$BEFORE_FILE"
    fi
  done

  # Add Docker GPG key and repo if missing
  if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  fi
  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi

  echo "✍🏻 Installing Docker Engine..."
  sudo apt-get update -y
  sudo apt-get install -y "\${TARGET_PKGS[@]}"
  sudo touch "$AFTER_FILE" && echo "   - marker at $AFTER_FILE"
  echo "✅ Docker installed"
else
  echo "🔄 Docker already set up, ensuring latest..."
  sudo apt-get update -y
  sudo apt-get install -y "\${TARGET_PKGS[@]}"
  echo "✅ Docker packages are current"
fi
EOF
then
  exit 0
else
  echo "❌ Remote execution failed" >&2
  exit 1
fi
