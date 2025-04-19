#!/usr/bin/env bash
set -euo pipefail

# 3-setup_firewall.sh
#
# Usage:
#   chmod +x 3-setup_firewall.sh
#   ./3-setup_firewall.sh --server-ip 1.2.3.4 [--ssh-port 2222] [--ssh-key-path ~/.ssh/id_rsa] [--rollback]
#
# Required:
#   --server-ip      IP address
#
# Optional (from .env or defaults):
#   --ssh-port       SSH Port (default: $SSH_PORT or 22)
#   --ssh-key-path   SSH Path (default: $SSH_KEY_PATH or ~/.ssh/id_rsa)
#   --rollback       Disable UFW and remove rules

print_usage() {
  cat <<EOF
Usage:
  $0 --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback]

Required:
  --server-ip      Server IP address or hostname

Optional:
  --ssh-port       SSH port (default: \$SSH_PORT or 22)
  --ssh-key-path   Path to your private SSH key (default: \$SSH_KEY_PATH or ~/.ssh/id_rsa)
  --rollback       Disable firewall and remove the rules

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
    *) echo "⚠️ Unknown parameter: $1" >&2; print_usage >&2; exit 1 ;;
  esac
done

# Validate
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
  if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<EOF
    set -e

    echo "⟳ Removing UFW rules…"
    delete_rule() {
      local rule="\$1"
      if sudo ufw status | grep -q "\$rule"; then
        sudo ufw delete allow "\$rule" >/dev/null 2>&1 && echo "   - rule '\$rule' removed"
      else
        echo "   - rule '\$rule' does not exist"
      fi
    }
    delete_rule "${SSH_PORT}/tcp"
    delete_rule "80/tcp"
    delete_rule "443/tcp"

    echo "⟳ Disabling UFW if active…"
    if sudo ufw status | grep -q "Status: inactive"; then
      echo "   - UFW is already inactive"
    else
      sudo ufw --force disable >/dev/null 2>&1 && echo "   - UFW disabled"
    fi

    echo "✅ Firewall rollback completed"
EOF
  then
    exit 0
  else
    echo "❌ Firewall rollback failed" >&2
    exit 1
  fi
fi

# ———— SETUP BRANCH ————
echo "🔑 Connecting as deploy@$SERVER_IP for SETUP"
if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<EOF
  set -e

  echo "⟳ Updating repositories and ensuring UFW is installed…"
  if ! dpkg -l | grep -q ufw; then
    sudo apt-get update -y
    sudo apt-get install -y ufw && echo "   - ufw installed"
  else
    echo "   - ufw is already installed"
  fi

  echo "⟳ Configuring UFW rules…"
  add_rule() {
    local rule="\$1"
    if ! sudo ufw status | grep -q "\$rule"; then
      sudo ufw allow "\$rule" >/dev/null 2>&1 && echo "   - rule '\$rule' added"
    else
      echo "   - rule '\$rule' already exists"
    fi
  }
  add_rule "${SSH_PORT}/tcp"
  add_rule "80/tcp"
  add_rule "443/tcp"

  echo "⟳ Enabling UFW logging…"
  if ! sudo ufw status verbose | grep -q "Logging: on"; then
    sudo ufw logging on >/dev/null 2>&1 && echo "   - logging enabled"
  else
    echo "   - logging was already enabled"
  fi

  echo "⟳ Enabling UFW…"
  if sudo ufw status | grep -q "Status: inactive"; then
    sudo ufw --force enable >/dev/null 2>&1 && echo "   - UFW enabled"
  else
    echo "   - UFW is already enabled"
  fi

EOF
then
  echo "✅ Firewall configured correctly on $SERVER_IP"
  exit 0
else
  echo "❌ SSH connection to deploy@$SERVER_IP failed or configuration error" >&2
  exit 1
fi
