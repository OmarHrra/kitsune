# Kitsune 🦊

<p align="center">
  <img src="kitsune-logo.png" alt="Kitsune Logo" width="180"/>
</p>

Kitsune is a lightweight toolkit built with Bash scripts to **provision**, **configure**, and **manage** a VPS server on DigitalOcean. It offers a streamlined environment for deploying web applications, optimized for use with [Kamal](https://github.com/basecamp/kamal). Each script is modular and can be executed individually or as part of a complete setup.

---

## 📝 Content

- [Prerequisites](#-prerequisites)
- [.env File](#️-env-file)
- [Scripts Structure](#-scripts-structure)
- [Usage](#-usage)
  - [Individual Execution](#individual-execution)
  - [Combined Execution](#combined-execution)
- [Rollback / Reversal](#-rollback--reversal)
- [Integration with Kamal](#-integration-with-kamal)

---

## 🔑 Prerequisites

1. Install doctl by following the documentation at [DigitalOcean doctl](https://docs.digitalocean.com/reference/doctl/).
2. Configure your DigitalOcean **API Key** with doctl:
   ```bash
   doctl auth init
   ```
3. Upload your SSH key to DigitalOcean, obtain its **ID**, and save it in `.env` as `SSH_KEY_ID`.
4. Ensure that you have `ssh` and `bash` available on your local machine.

## ⚙️ `.env` File

Create a `.env` file at the root of the project with the following variables:

```dotenv
# DigitalOcean Droplet defaults
DROPLET_NAME=               # Ex: "app-prod"
REGION=                     # Ex: "sfo3"
SIZE=                       # Ex: "s-1vcpu-1gb"
IMAGE=                      # Ex: "ubuntu-22-04-x64"
SSH_KEY_ID=                 # Your SSH key ID in DigitalOcean
SSH_KEY_PATH=~/.ssh/id_rsa  # Path to your private key
TAG_NAME=                   # Ex: "rails-prod"

# SSH configuration
SSH_PORT=22                 # Optional, default is 22
```

> 💡 Ensure that the file is not committed to a public repository.

---

## 🗂️ Scripts Structure

```
scripts/
├─ 1-provision/
│  ├─ 1-create_droplet.sh
│  ├─ 2-setup_user.sh
│  ├─ 3-setup_firewall.sh
│  ├─ 4-setup_unattended.sh
│  └─ all.sh
├─ 2-docker/
│  ├─ 1-setup_docker_prereqs.sh
│  ├─ 2-install_docker_engine.sh
│  ├─ 3-postinstall_docker.sh
│  └─ all.sh
└─ lib/
   └─ load_env.sh
```

| Script                           | Description                                                                                             |
|----------------------------------|---------------------------------------------------------------------------------------------------------|
| `1-create_droplet.sh`            | Creates or displays a Droplet on DigitalOcean. Optionally deletes if `--rollback` is used.              |
| `2-setup_user.sh`                | Creates the `deploy` user, enables passwordless sudo, and hardens SSH.                                  |
| `3-setup_firewall.sh`            | Installs and configures UFW (SSH, HTTP, HTTPS rules).                                                   |
| `4-setup_unattended.sh`          | Enables and configures automatic security updates.                                                      |
| `all.sh` (provision)             | Sequentially executes the 4 provisioning scripts.                                                       |
| `1-setup_docker_prereqs.sh`      | Installs prerequisites for Docker (certificates, repositories).                                         |
| `2-install_docker_engine.sh`     | Adds the Docker repository and installs the Docker engine.                                              |
| `3-postinstall_docker.sh`        | Starts and enables Docker, adds the `deploy` user to the `docker` group, and creates a private network. |
| `all.sh` (docker)                | Executes the 3 Docker scripts in order or reverts them with `--rollback`.                               |

---

## 🚀 Usage

### Individual Execution

Each script can be run separately:

```bash
# VPS Provisioning
chmod +x scripts/1-provision/1-create_droplet.sh
scripts/1-provision/1-create_droplet.sh --droplet-name my-app --region nyc1

# User, firewall, or unattended configuration:
scripts/1-provision/2-setup_user.sh --server-ip x.x.x.x
scripts/1-provision/3-setup_firewall.sh --server-ip x.x.x.x
scripts/1-provision/4-setup_unattended.sh --server-ip x.x.x.x

# Docker configuration:
scripts/2-docker/1-setup_docker_prereqs.sh --server-ip x.x.x.x
scripts/2-docker/2-install_docker_engine.sh --server-ip x.x.x.x
scripts/2-docker/3-postinstall_docker.sh --server-ip x.x.x.x
```

### Combined Execution

To create and configure everything in a single step:

```bash
chmod +x scripts/1-provision/all.sh
scripts/1-provision/all.sh --ssh-port 22 --ssh-key-path ~/.ssh/id_rsa
```

And to rollback/reverse configurations:

```bash
scripts/1-provision/all.sh --rollback [--keep-server]
```

Similarly, for Docker:

```bash
chmod +x scripts/2-docker/all.sh
scripts/2-docker/all.sh --server-ip x.x.x.x
# Complete rollback of Docker:
scripts/2-docker/all.sh --server-ip x.x.x.x --rollback
```

---

## 🔄 Rollback / Reversal

- Append `--rollback` to any script to undo its changes.
- In `all.sh`, `--rollback` reverses the steps in the opposite order (unattended → firewall → user → droplet).
- The `--keep-server` flag prevents deleting the Droplet during a global rollback.

---

## 🔗 Integration with Kamal

After provisioning and configuring the server, you can deploy your app with [Kamal](https://github.com/basecamp/kamal). The basic steps are:

1. Add your server as a target in `kamal.yml`.
2. Run:
   ```bash
   kamal setup
   ```

