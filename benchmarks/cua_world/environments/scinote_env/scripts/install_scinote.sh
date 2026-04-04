#!/bin/bash
set -e

echo "=== Installing SciNote ELN dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install prerequisites
apt-get install -y \
    ca-certificates \
    curl \
    wget \
    git \
    make \
    gnupg \
    lsb-release

# Install Docker from official repo (needed for BuildKit support)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker service
systemctl enable docker
systemctl start docker

# Enable BuildKit by default
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "features": {
    "buildkit": true
  }
}
EOF
systemctl restart docker

# Add ga user to docker group
usermod -aG docker ga

# Install Firefox and GUI automation tools
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    imagemagick \
    scrot

# Install Python packages for verification
apt-get install -y python3-pip
pip3 install requests psycopg2-binary 2>/dev/null || pip install requests psycopg2-binary 2>/dev/null || true

# Clone SciNote repository
cd /home/ga
git clone --depth 1 --branch develop https://github.com/scinote-eln/scinote-web.git
chown -R ga:ga /home/ga/scinote-web

echo "=== SciNote dependencies installation complete ==="
