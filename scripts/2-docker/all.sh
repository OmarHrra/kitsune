#!/usr/bin/env bash
set -euo pipefail

# all_docker.sh
#
# Usage:
#   chmod +x all_docker.sh
#   ./all_docker.sh --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback] [-h|--help]
#
# Default: Runs Docker prerequisites, engine install, and post-install configuration.
# --rollback: Executes each sub-script in rollback mode (reverse order).
# -h, --help: Show this help message and exit.

print_usage() {
  cat <<EOF
Usage:
  $0 --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback] [-h|--help]

Options:
  --server-ip      Server IP address or hostname (required)
  --ssh-port       SSH port for sub-scripts (default: \$SSH_PORT or 22)
  --ssh-key-path   Path to SSH private key (default: \$SSH_KEY_PATH or ~/.ssh/id_rsa)
  --rollback       Run sub-scripts with --rollback
  -h, --help       Show this help and exit
EOF
  exit 1
}

# ————————— LOAD ENVIRONMENT —————————
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/load_env.sh"

# Script paths
PREREQS_SCRIPT="$SCRIPT_DIR/1-setup_docker_prereqs.sh"
INSTALL_SCRIPT="$SCRIPT_DIR/2-install_docker_engine.sh"
POST_SCRIPT="$SCRIPT_DIR/3-postinstall_docker.sh"

# Defaults
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
ROLLBACK=false

# Parse flags
if [ $# -eq 0 ]; then
  print_usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      ;;
    --rollback)
      ROLLBACK=true; shift
      ;;
    --server-ip)
      SERVER_IP="$2"; shift 2
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

# Validate
if [ -z "${SERVER_IP:-}" ]; then
  echo "❌ --server-ip is required" >&2
  exit 1
fi

# MAIN LOGIC
if [ "$ROLLBACK" = false ]; then
  echo "🐳 Running full Docker setup on $SERVER_IP..."
  bash "$PREREQS_SCRIPT"  --server-ip "$SERVER_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH"
  bash "$INSTALL_SCRIPT" --server-ip "$SERVER_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH"
  bash "$POST_SCRIPT"  --server-ip "$SERVER_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH"
else
  echo "🔄 Rolling back Docker configuration on $SERVER_IP..."
  bash "$POST_SCRIPT"  --server-ip "$SERVER_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH" --rollback
  bash "$INSTALL_SCRIPT" --server-ip "$SERVER_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH" --rollback
  bash "$PREREQS_SCRIPT" --server-ip "$SERVER_IP" --ssh-port "$SSH_PORT" --ssh-key-path "$SSH_KEY_PATH" --rollback
fi

echo "🎉 Done!"
