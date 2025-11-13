#!/bin/bash
set -e

# -------------------------
# --- Detect package manager ---
# -------------------------
if command -v apt &> /dev/null; then
    PKG_MANAGER="apt"
    UPDATE_CMD="sudo apt update"
    INSTALL_CMD="sudo apt install -y"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="sudo dnf makecache"
    INSTALL_CMD="sudo dnf install -y"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    UPDATE_CMD="sudo yum makecache"
    INSTALL_CMD="sudo yum install -y"
else
    echo "❌ Unsupported package manager. Install dependencies manually."
    exit 1
fi

echo "Using package manager: $PKG_MANAGER"

# -------------------------
# --- Install dependencies ---
# -------------------------
DEPENDENCIES=(git cron curl awscli)

echo "Updating package lists..."
$UPDATE_CMD

for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        echo "Installing $dep..."
        $INSTALL_CMD "$dep"
    else
        echo "✅ $dep already installed."
    fi
done

# -------------------------
# --- Generate SSH Key ---
# -------------------------
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    echo "Generating new SSH key..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "$(whoami)@$(hostname)"
else
    echo "✅ SSH key already exists."
fi

# -------------------------
# --- Install Tailscale ---
# -------------------------
if ! command -v tailscale &> /dev/null; then
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
else
    echo "✅ Tailscale already installed."
fi

# -------------------------
# --- Install Docker & Docker Compose CLI plugin ---
# -------------------------
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

# Install Docker Compose plugin for modern `docker compose`
if ! docker compose version &> /dev/null; then
    echo "Installing Docker Compose CLI plugin..."
    DOCKER_CONFIG_DIR="${HOME}/.docker/cli-plugins"
    mkdir -p "$DOCKER_CONFIG_DIR"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
        -o "$DOCKER_CONFIG_DIR/docker-compose"
    chmod +x "$DOCKER_CONFIG_DIR/docker-compose"
else
    echo "✅ Docker Compose plugin already installed."
fi

# -------------------------
# --- Create AWS credentials template ---
# -------------------------
AWS_DIR="$HOME/.aws"
AWS_CREDS_FILE="$AWS_DIR/credentials"

mkdir -p "$AWS_DIR"

if [ ! -f "$AWS_CREDS_FILE" ]; then
    cat > "$AWS_CREDS_FILE" <<EOL
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
region = eu-west-2
EOL
    echo
    echo "⚠️ AWS credentials template created at $AWS_CREDS_FILE"
    echo "Please edit this file and add your actual AWS credentials manually."
else
    echo "✅ AWS credentials file already exists at $AWS_CREDS_FILE"
fi

# -------------------------
# --- Ensure services start on boot ---
# -------------------------
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

# -------------------------
# --- Show SSH public key for GitHub ---
# -------------------------
PUB_KEY="$SSH_KEY.pub"
echo
echo "Copy the SSH public key below to GitHub or other services:"
echo "-----------------------------------------------------------"
cat "$PUB_KEY"
echo "-----------------------------------------------------------"

# -------------------------
# --- Start Tailscale with SSH & Exit Node ---
# -------------------------
echo
echo "Starting Tailscale with SSH and advertising as exit node..."
sudo tailscale up --ssh --advertise-exit-node

echo
echo "✅ Setup complete!"
