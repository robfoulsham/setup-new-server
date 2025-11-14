#!/bin/bash
set -e

# -------------------------
# --- Log file ---
# -------------------------
LOG_FILE="/tmp/setup.log"
echo "Setup logs will be saved to $LOG_FILE"

# -------------------------
# --- Colors for output ---
# -------------------------
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

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
    echo -e "${RED}❌ Unsupported package manager. Install dependencies manually.${NC}"
    exit 1
fi

echo -e "${GREEN}Using package manager: $PKG_MANAGER${NC}"

# -------------------------
# --- Install dependencies ---
# -------------------------
DEPENDENCIES=(git cron curl unzip)

echo -e "\n=============================="
echo "       Installing Dependencies       "
echo "=============================="

$UPDATE_CMD &>> "$LOG_FILE"
for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        echo "Installing $dep..."
        $INSTALL_CMD "$dep" &>> "$LOG_FILE" && echo -e "${GREEN}✅ $dep installed${NC}" || echo -e "${RED}❌ Failed to install $dep (see $LOG_FILE)${NC}"
    else
        echo -e "${GREEN}✅ $dep already installed.${NC}"
    fi
done

# -------------------------
# --- Install AWS CLI v2 ---
# -------------------------
echo -e "\n=============================="
echo "       Installing AWS CLI v2       "
echo "=============================="

if ! command -v aws &> /dev/null; then
    TMP_DIR=$(mktemp -d)
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP_DIR/awscliv2.zip" &>> "$LOG_FILE"
    unzip "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR" &>> "$LOG_FILE"
    sudo "$TMP_DIR/aws/install" &>> "$LOG_FILE"
    rm -rf "$TMP_DIR"
    echo -e "${GREEN}✅ AWS CLI installed${NC}"
else
    echo -e "${GREEN}✅ AWS CLI already installed.${NC}"
fi
aws --version

# -------------------------
# --- Install Tailscale ---
# -------------------------
echo -e "\n=============================="
echo "       Installing Tailscale       "
echo "=============================="

if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh &>> "$LOG_FILE"
    echo -e "${GREEN}✅ Tailscale installed${NC}"
else
    echo -e "${GREEN}✅ Tailscale already installed.${NC}"
fi

# -------------------------
# --- Install Docker (latest official) ---
# -------------------------
echo -e "\n=============================="
echo "       Installing Docker       "
echo "=============================="

if [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt remove -y docker docker-engine docker.io containerd runc &>> "$LOG_FILE" || true
    sudo apt update &>> "$LOG_FILE"
    sudo apt install -y ca-certificates curl gnupg &>> "$LOG_FILE"
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update &>> "$LOG_FILE"
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &>> "$LOG_FILE"
else
    $INSTALL_CMD docker &>> "$LOG_FILE" || true
fi

echo -e "${GREEN}✅ Docker installed${NC}"
docker --version
docker buildx version || true
docker compose version || true

# -------------------------
# --- Ensure services start on boot ---
# -------------------------
SERVICES=(cron tailscaled docker)

for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc"; then
        echo -e "${GREEN}✅ $svc service exists.${NC}"
        echo "Enabling $svc service..."
        sudo systemctl enable "$svc" &>> "$LOG_FILE"
        echo "Starting $svc service..."
        sudo systemctl start "$svc" &>> "$LOG_FILE"
    else
        echo -e "${YELLOW}⚠️  $svc service not found. Skipping enable/start.${NC}"
    fi
done

# -------------------------
# --- Start Tailscale with SSH & Exit Node ---
# -------------------------
echo -e "\n=============================="
echo "   Tailscale login URL below   "
echo "=============================="

sudo tailscale up --ssh --advertise-exit-node

echo -e "\n=============================="
echo "✅ Tailscale setup complete!"

# -------------------------
# --- Install Shared SSH Key from Proxmox host ---
# -------------------------
SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
SSH_PUB="$SSH_DIR/id_ed25519.pub"

echo -e "\n=============================="
echo "   Installing shared SSH key   "
echo "=============================="

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$SSH_KEY" ]; then
    scp -o StrictHostKeyChecking=no root@proxmox:/root/.ssh/id_ed25519_shared "$SSH_KEY"
    chmod 600 "$SSH_KEY"
    echo -e "${GREEN}✅ SSH private key copied${NC}"
else
    echo -e "${GREEN}✅ SSH private key already exists at $SSH_KEY${NC}"
fi

if [ ! -f "$SSH_PUB" ]; then
    scp -o StrictHostKeyChecking=no root@proxmox:/root/.ssh/id_ed25519_shared.pub "$SSH_PUB"
    chmod 644 "$SSH_PUB"
    echo -e "${GREEN}✅ SSH public key copied${NC}"
else
    echo -e "${GREEN}✅ SSH public key already exists at $SSH_PUB${NC}"
fi

# -------------------------
# --- Create / Copy AWS credentials ---
# -------------------------
AWS_DIR="$HOME/.aws"
AWS_CREDS_FILE="$AWS_DIR/credentials"
mkdir -p "$AWS_DIR"

if ! ssh root@proxmox test -f /root/.aws/credentials &> /dev/null; then
    if [ ! -f "$AWS_CREDS_FILE" ]; then
        cat > "$AWS_CREDS_FILE" <<EOL
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
region = eu-west-2
EOL
        echo -e "${YELLOW}⚠️ AWS credentials template created at $AWS_CREDS_FILE${NC}"
        echo "edit this file to add  actual AWS credentials manually."
    else
        echo -e "${GREEN}✅ AWS credentials file already exists at $AWS_CREDS_FILE${NC}"
    fi
else
    echo "Copying AWS credentials from root@proxmox..."
    scp -o StrictHostKeyChecking=no root@proxmox:/root/.aws/credentials "$AWS_CREDS_FILE"
    chmod 600 "$AWS_CREDS_FILE"
    echo -e "${GREEN}✅ AWS credentials copied from proxmox${NC}"
fi

echo "✅ Setup complete!"
echo "All verbose logs are saved at: $LOG_FILE"
echo "=============================="
