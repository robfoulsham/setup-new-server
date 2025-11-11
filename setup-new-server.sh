#!/bin/bash
set -e

# --- Detect package manager ---
if command -v apt &> /dev/null; then
    PKG_MANAGER="apt"
    INSTALL_CMD="sudo apt update && sudo apt install -y"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="sudo dnf install -y"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    INSTALL_CMD="sudo yum install -y"
else
    echo "❌ Unsupported package manager. Install dependencies manually."
    exit 1
fi

echo "Using package manager: $PKG_MANAGER"

# --- Dependencies ---
DEPENDENCIES=(git cron curl)

for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        echo "Installing $dep..."
        $INSTALL_CMD "$dep"
    else
        echo "✅ $dep already installed."
    fi
done

# --- Generate SSH Key ---
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    echo "Generating new SSH key..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "$(whoami)@$(hostname)"
else
    echo "✅ SSH key already exists."
fi

# --- Install Tailscale ---
if ! command -v tailscale &> /dev/null; then
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
else
    echo "✅ Tailscale already installed."
fi

# --- Install Docker ---
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        sudo apt update
        sudo apt install -y docker.io
    else
        $INSTALL_CMD docker
    fi
else
    echo "✅ Docker already installed."
fi

# --- Ensure services start on boot ---
SERVICES=(cron tailscaled docker)

for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc"; then
        echo "✅ $svc service exists."
        echo "Enabling $svc service..."
        sudo systemctl enable "$svc"
        echo "Starting $svc service..."
        sudo systemctl start "$svc"
    else
        echo "⚠️  $svc service not found. Skipping enable/start."
    fi
done

# --- Copy SSH Public Key to Clipboard ---
PUB_KEY="$SSH_KEY.pub"
echo

echo "copy ssh key from below for github:"
cat "$PUB_KEY"

# --- Tailscale Up with SSH & Exit Node ---
echo
echo "Starting Tailscale with SSH and advertising as exit node..."
sudo tailscale up --ssh --advertise-exit-node

echo
echo "✅ Setup complete."
