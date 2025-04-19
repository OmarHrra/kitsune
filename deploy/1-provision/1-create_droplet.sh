#!/usr/bin/env bash

# 1-create_droplet.sh
# Usage: chmod +x 1-create_droplet.sh && ./1-create_droplet.sh
# Returns the ID and public IP of the new Droplet

# ——————————————————————————————————————————————
# Available SIZE options (slug — vCPU — RAM — Approx. price/month)
# s-1vcpu-1gb    — 1 vCPU   — 1 GB  — $6
# s-1vcpu-2gb    — 1 vCPU   — 2 GB  — $12
# s-2vcpu-2gb    — 2 vCPU   — 2 GB  — $18
# s-2vcpu-4gb    — 2 vCPU   — 4 GB  — $24
# s-4vcpu-8gb    — 4 vCPU   — 8 GB  — $48
# s-8vcpu-16gb   — 8 vCPU   — 16 GB — $96
# s-16vcpu-32gb  — 16 vCPU  — 32 GB — $192
#   (See https://www.digitalocean.com/pricing/ for more options)
# ——————————————————————————————————————————————
# Available REGION options (slug — location)
# nyc1   — New York 1 (USA)
# sfo3   — San Francisco 3 (USA)
# ams3   — Amsterdam 3 (Netherlands)
# fra1   — Frankfurt 1 (Germany)
# lon1   — London 1 (UK)
# tor1   — Toronto 1 (Canada)
# blr1   — Bangalore 1 (India)
# sgp1   — Singapore 1 (Singapore)
#   (See full list with `doctl compute region list`)
# ——————————————————————————————————————————————

# ————————— LOAD ENVIRONMENT VARIABLES —————————
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/load_env.sh"

# ————————— VARIABLES WITH DEFAULTS —————————
DROPLET_NAME="${DROPLET_NAME:-app-prod}"             # Identifier name for your Droplet
REGION="${REGION:-sfo3}"                             # Region in which to create the VPS
SIZE="${SIZE:-s-1vcpu-1gb}"                          # Plan (see options above)
IMAGE="${IMAGE:-ubuntu-22-04-x64}"                   # Base image (Ubuntu 22.04 LTS)
SSH_KEY_ID="${SSH_KEY_ID:?You must set SSH_KEY_ID in .env or as an env var}"  # Your SSH key fingerprint or ID
TAG_NAME="${TAG_NAME:-rails-prod}"                   # Tag for organizing resources

# Create the Droplet and wait until it's done
doctl compute droplet create "$DROPLET_NAME" \
  --region "$REGION" \
  --size "$SIZE" \
  --image "$IMAGE" \
  --ssh-keys "$SSH_KEY_ID" \
  --tag-names "$TAG_NAME" \
  --wait \
  --format ID,Name,PublicIPv4 \
  --no-header

echo "✅ Droplet created successfully"
