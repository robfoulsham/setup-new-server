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
DEPENDENCIES=(git cron curl unzip)

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
# --- Install AWS CLI v2 ---
# -------------------------
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI v2..."
    TMP_DIR=$(mktemp -d)
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP_DIR/awscliv2.zip"
    unzip "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR"
    sudo "$TMP_DIR/aws/install"
    rm -rf "$TMP_DIR"
else
    echo "✅ AWS CLI already installed."
fi

aws --version

# -------------------------
# --- Generate SSH Key ---
# -------------------------
# SSH_KEY="$HOME/.ssh/id_ed25519"
# if [ ! -f "$SSH_KEY" ]; then
#     echo "Generating new SSH key..."
#     mkdir -p "$HOME/.ssh"
#     ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "$(whoami)@$(hostname)"
# else
#     echo "✅ SSH key already exists."
# fi

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
# --- Install Docker (latest, official) ---
# -------------------------
echo "Installing latest Docker from official Docker repository..."

if [ "$PKG_MANAGER" = "apt" ]; then
    # Remove any old Docker packages
    sudo apt remove -y docker docker-engine docker.io containerd runc || true

    # Install dependencies for Docker repo
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg

    # Add Docker’s official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
      $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine + Buildx + Compose plugin
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

else
    # Fallback for yum/dnf systems (best possible without changing script)
    echo "Installing Docker using distro package (non-apt system detected)..."
    $INSTALL_CMD docker || true
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
# PUB_KEY="$SSH_KEY.pub"
# echo
# echo "Copy the SSH public key below to GitHub or other services:"
# echo "-----------------------------------------------------------"
# cat "$PUB_KEY"
# echo "-----------------------------------------------------------"

# -------------------------
# --- Start Tailscale with SSH & Exit Node ---
# -------------------------
echo
echo "Starting Tailscale with SSH and advertising as exit node..."
sudo tailscale up --ssh --advertise-exit-node

# -------------------------
# --- Install Shared SSH Key from Proxmox host ---
# -------------------------
SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
SSH_PUB="$SSH_DIR/id_ed25519.pub"

echo "Setting up shared SSH key from root@proxmox..."

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Copy private key
if [ ! -f "$SSH_KEY" ]; then
    echo "Copying shared private key from root@proxmox..."
    sudo scp root@proxmox:/root/.ssh/id_ed25519_shared "$SSH_KEY"
    chmod 600 "$SSH_KEY"
else
    echo "✅ SSH private key already exists at $SSH_KEY"
fi

# Copy public key
if [ ! -f "$SSH_PUB" ]; then
    echo "Copying shared public key from root@proxmox..."
    sudo scp root@proxmox:/root/.ssh/id_ed25519_shared.pub "$SSH_PUB"
    chmod 644 "$SSH_PUB"
else
    echo "✅ SSH public key already exists at $SSH_PUB"
fi

echo "Shared SSH key installed."


echo
echo "✅ Setup complete!"
