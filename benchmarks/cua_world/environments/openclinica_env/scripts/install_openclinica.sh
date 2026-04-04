#!/bin/bash
set -e

echo "=== Installing OpenClinica Dependencies ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Add Docker GPG key and repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || {
    echo "Docker CE install failed, trying docker.io..."
    apt-get install -y docker.io docker-compose
}

# Install docker-compose standalone if needed
if ! command -v docker-compose &>/dev/null; then
    if docker compose version &>/dev/null; then
        # Create wrapper for 'docker compose' -> 'docker-compose'
        cat > /usr/local/bin/docker-compose << 'DCEOF'
#!/bin/bash
exec docker compose "$@"
DCEOF
        chmod +x /usr/local/bin/docker-compose
    else
        curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
fi

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ga user to docker group
usermod -aG docker ga || true

# Install Firefox and GUI tools
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    scrot \
    imagemagick \
    xclip \
    jq \
    python3-pip \
    python3-psycopg2

# Pre-pull Docker images (speeds up post_start)
echo "Pre-pulling Docker images..."
docker pull postgres:9.5 || echo "WARNING: Failed to pull postgres:9.5"
docker pull piegsaj/openclinica:oc-3.13 || echo "WARNING: Failed to pull openclinica image"

echo "=== OpenClinica Dependencies Installation Complete ==="
