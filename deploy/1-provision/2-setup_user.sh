#!/usr/bin/env bash
set -euo pipefail

# 2-setup_user.sh
#
# Usage:
#   chmod +x 2-setup_user.sh
#   ./2-setup_user.sh --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback]
#
# Required:
#   --server-ip      IP address
#
# Optional (from .env or defaults):
#   --ssh-port       SSH Port (default: $SSH_PORT or 22)
#   --ssh-key-path   SSH Path (default: $SSH_KEY_PATH or ~/.ssh/id_rsa)
#   --rollback       Perform rollback instead of setup

print_usage() {
  cat <<EOF
Usage:
  $0 --server-ip IP [--ssh-port PORT] [--ssh-key-path PATH] [--rollback]

Required:
  --server-ip    Server IP address or hostname

Optional:
  --ssh-port     SSH port (default: \$SSH_PORT or 22)
  --ssh-key-path Path to your private SSH key (default: \$SSH_KEY_PATH or ~/.ssh/id_rsa)
  --rollback     Removes user 'deploy', sudoers, and reverts SSH settings

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

# Default values
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
    --server-ip)    SERVER_IP="$2";       shift 2 ;;
    --ssh-port)     SSH_PORT="$2";        shift 2 ;;
    --ssh-key-path) SSH_KEY_PATH="$2";    shift 2 ;;
    --rollback)     ROLLBACK=true;        shift   ;;
    -h|--help)      print_usage; exit 0  ;;
    *) echo "⚠️  Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
  esac
done

# Validate
if [[ -z "${SERVER_IP:-}" ]]; then
  echo "❌ --server-ip is required" >&2
  exit 1
fi

# SSH options array
SSH_OPTS=(
  -i "$SSH_KEY_PATH"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -p "$SSH_PORT"
)

# ————————— DETECT REMOTE USER para SETUP —————————
if [ "$ROLLBACK" = false ]; then
  if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" id &>/dev/null; then
    REMOTE_USER="deploy"
  else
    REMOTE_USER="root"
  fi
  echo "🔑 Connecting as $REMOTE_USER@$SERVER_IP"
fi

# ———— ROLLBACK BRANCH ————
if [ "$ROLLBACK" = true ]; then
  echo "🔑 Attempting SSH config restore as deploy@$SERVER_IP (rollback=true)"
  if ssh "${SSH_OPTS[@]}" deploy@"$SERVER_IP" bash <<'EOF'
    set -e
    echo "⟳ Backing up SSH config…"
    sudo test -f /etc/ssh/sshd_config.bak || sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak && echo "   - sshd_config backed up"
    echo "⟳ Restoring SSH config…"
    # Enable root login
    grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config \
      || sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config && echo "   - PermitRootLogin yes"
    # Enable password auth
    grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config \
      || sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config && echo "   - PasswordAuthentication yes"
    sudo systemctl restart sshd && echo "   - sshd restarted"
EOF
  then
    echo "✅ SSH config restored, closing deploy session"
  else
    echo "⚠️ Skipping SSH config restore: deploy user not available or restore failed" >&2
  fi

  echo "🔑 Reconnecting as root@$SERVER_IP"
  if ssh "${SSH_OPTS[@]}" root@"$SERVER_IP" bash <<'EOF'
    set -e
    echo "⟳ Removing sudoers file…"
    if [ -f /etc/sudoers.d/deploy ]; then
      sudo rm -f /etc/sudoers.d/deploy && echo "   - /etc/sudoers.d/deploy removed"
    else
      echo "   - no sudoers file to remove"
    fi

    echo "⟳ Killing remaining processes for deploy…"
    sudo pkill -u deploy || echo "   - no processes found"

    echo "⟳ Deleting deploy user…"
    if id deploy &>/dev/null; then
      if command -v deluser &>/dev/null; then
        sudo deluser --remove-home deploy && echo "   - deploy user removed"
      else
        sudo userdel -r deploy && echo "   - deploy user removed"
      fi
    else
      echo "   - deploy user does not exist"
    fi
EOF
  then
    echo "✅ Rollback completed on $SERVER_IP"
    exit 0
  else
    echo "❌ Failed rollback cleanup as root" >&2
    exit 1
  fi
fi

# ———— SETUP BRANCH ————
if ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$SERVER_IP" bash <<'EOF'
  set -e

  echo "⟳ Creating deploy user…"
  if ! id deploy &>/dev/null; then
    if command -v adduser &>/dev/null; then
      sudo adduser --disabled-password --gecos "" deploy && echo "   - user 'deploy' created"
    else
      sudo useradd -m -s /bin/bash deploy && echo "   - user 'deploy' created"
    fi
    sudo usermod -aG sudo deploy && echo "   - 'deploy' added to sudo"
  else
    echo "   - user 'deploy' already exists"
  fi

  echo "⟳ Configuring passwordless sudo…"
  if [ ! -f /etc/sudoers.d/deploy ]; then
    echo 'deploy ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/deploy \
      && sudo chmod 440 /etc/sudoers.d/deploy \
      && echo "   - sudoers entry created"
  else
    echo "   - sudoers entry exists"
  fi

  echo "⟳ Backing up SSH config…"
  sudo test -f /etc/ssh/sshd_config.bak || sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak && echo "   - sshd_config backed up"

  echo "⟳ Hardening SSH…"
  grep -q '^PermitRootLogin no' /etc/ssh/sshd_config \
    || sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config && echo "   - PermitRootLogin no"
  grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config \
    || sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config && echo "   - PasswordAuthentication no"
  sudo systemctl restart sshd && echo "   - sshd restarted"

  echo "⟳ Installing SSH keys for deploy…"
  if [ ! -f /home/deploy/.ssh/authorized_keys ]; then
    sudo mkdir -p /home/deploy/.ssh
    sudo cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
    sudo chown -R deploy:deploy /home/deploy/.ssh
    sudo chmod 700 /home/deploy/.ssh
    sudo chmod 600 /home/deploy/.ssh/authorized_keys
    echo "   - authorized_keys copied"
  else
    echo "   - authorized_keys already present"
  fi
EOF
then
  echo "✅ User and SSH configuration completed on $SERVER_IP"
  exit 0
else
  echo "❌ SSH configuration failed on $SERVER_IP" >&2
  exit 1
fi
