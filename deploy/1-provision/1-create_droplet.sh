#!/usr/bin/env bash
set -euo pipefail

# 1-create_droplet.sh
#
# Usage:
#   chmod +x 1-create_droplet.sh
#   ./1-create_droplet.sh [--droplet-name NAME] [--region SLUG] [--size SLUG] [--image SLUG] [--tag TAG] [--rollback] [-h | --help]
#
# Required:
#   SSH_KEY_ID in .env or as env var (export SSH_KEY_ID=your-key-id)
#
# Optional flags (overrides env or defaults):
#   --droplet-name NAME   Identifier for your Droplet (default: app-prod)
#   --region SLUG          Region slug (default: sfo3)
#   --size SLUG            Plan slug (default: s-1vcpu-1gb)
#   --image SLUG           Image (default: ubuntu-22-04-x64)
#   --tag TAG              Tag name (default: rails‑prod)
#   --rollback             Delete the Droplet if it exists
#   -h, --help             Show this help and exit
#
# Examples:
#   # Create (first or subsequent runs)
#   ./1-create_droplet.sh
#   ./1-create_droplet.sh --droplet-name my-app --region nyc1
#
#   # Rollback (delete) the droplet
#   ./1-create_droplet.sh --rollback
#   ./1-create_droplet.sh --droplet-name my-app --rollback

print_usage() {
  cat <<EOF
Usage:
  $0 [--droplet-name NAME] [--region SLUG] [--size SLUG]
     [--image SLUG] [--tag TAG] [--rollback] [-h | --help]

Required:
  SSH_KEY_ID       must be set in .env or exported in your shell

Options:
  --droplet-name   Name for the Droplet (default: \$DROPLET_NAME or app-prod)
  --region         Region slug (default: \$REGION or sfo3)
  --size           Size slug (default: \$SIZE or s-1vcpu-1gb)
  --image          Image slug (default: \$IMAGE or ubuntu-22-04-x64)
  --tag            Tag to assign (default: \$TAG_NAME or rails-prod)
  --rollback       Remove the Droplet if it exists
  -h, --help       Show this help and exit

Examples:
  # Create
  $0
  $0 --droplet-name web1 --region nyc1 --size s-2vcpu-2gb

  # Rollback
  $0 --rollback
  $0 --droplet-name web1 --rollback
EOF
}

# ————————— LOAD ENVIRONMENT —————————
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/load_env.sh"

# ————————— DEFAULTS —————————
DROPLET_NAME="${DROPLET_NAME:-app-prod}"
REGION="${REGION:-sfo3}"
SIZE="${SIZE:-s-1vcpu-1gb}"
IMAGE="${IMAGE:-ubuntu-22-04-x64}"
TAG_NAME="${TAG_NAME:-rails-prod}"
ROLLBACK=false

# ————————— PARSE FLAGS —————————
while [[ $# -gt 0 ]]; do
  case "$1" in
    --droplet-name) DROPLET_NAME="$2"; shift 2 ;;
    --region)       REGION="$2";       shift 2 ;;
    --size)         SIZE="$2";         shift 2 ;;
    --image)        IMAGE="$2";        shift 2 ;;
    --tag)          TAG_NAME="$2";     shift 2 ;;
    --rollback)     ROLLBACK=true;     shift   ;;
    -h|--help)      print_usage; exit 0 ;;
    *) echo "⚠️  Unknown option: $1" >&2; print_usage >&2; exit 1 ;;
  esac
done

# ————————— VALIDATE —————————
: "${SSH_KEY_ID:?You must set SSH_KEY_ID in .env or as an env var}"

# Function to look up existing droplet by name
get_droplet_info() {
  # Returns: ID PublicIPv4 (or empty)
  doctl compute droplet list \
    --format ID,Name,PublicIPv4 \
    --no-header \
    | awk -v name="$DROPLET_NAME" '$2 == name { print $1, $3; exit }'
}

# Fetch current state
existing=$(get_droplet_info || true)

if [ "$ROLLBACK" = true ]; then
  if [ -n "$existing" ]; then
    droplet_id=$(awk '{print $1}' <<<"$existing")
    echo "✍🏻 Deleting Droplet '$DROPLET_NAME' (ID: $droplet_id)..."
    doctl compute droplet delete "$droplet_id" --force \
      && echo "✅ Droplet deleted" \
      || { echo "❌ Failed to delete droplet"; exit 1; }
  else
    echo "✅ Nothing to delete: Droplet '$DROPLET_NAME' does not exist"
  fi
  exit 0
fi

# ———— CREATE OR SHOW EXISTING ————
if [ -n "$existing" ]; then
  droplet_id=$(awk '{print $1}' <<<"$existing")
  droplet_ip=$(awk '{print $2}' <<<"$existing")
  echo "✅ Droplet '$DROPLET_NAME' already exists (ID: $droplet_id, IP: $droplet_ip)"
  exit 0
fi

# Create new droplet
echo "✍🏻 Creating Droplet '$DROPLET_NAME'..."
droplet_info=$(doctl compute droplet create "$DROPLET_NAME" \
  --region "$REGION" \
  --size "$SIZE" \
  --image "$IMAGE" \
  --ssh-keys "$SSH_KEY_ID" \
  --tag-names "$TAG_NAME" \
  --wait \
  --format ID,Name,PublicIPv4 \
  --no-header)
echo "$droplet_info"
echo "✅ Droplet '$DROPLET_NAME' created successfully"
exit 0
