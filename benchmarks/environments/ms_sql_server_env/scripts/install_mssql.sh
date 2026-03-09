#!/bin/bash
# Microsoft SQL Server 2022 Installation Script (pre_start hook)
# Installs Docker for SQL Server container and Azure Data Studio for GUI management

set -e

echo "=== Installing Microsoft SQL Server 2022 Environment ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "Updating package lists..."
apt-get update

# Install Docker and Docker Compose
echo "Installing Docker..."
apt-get install -y docker.io docker-compose

# Start and enable Docker service
echo "Starting Docker service..."
systemctl enable docker
systemctl start docker

# Add ga user to docker group (allows running docker without sudo)
usermod -aG docker ga

# Install dependencies for Azure Data Studio
echo "Installing dependencies for Azure Data Studio..."
apt-get install -y \
    libxss1 \
    libgconf-2-4 \
    libunwind8 \
    libasound2 \
    libgtk-3-0 \
    libx11-xcb1 \
    libxcb-dri3-0 \
    libdrm2 \
    libgbm1 \
    libnspr4 \
    libnss3 \
    libxkbcommon0

# Install GUI automation tools
echo "Installing automation tools..."
apt-get install -y \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    wget \
    unzip \
    gnupg2

# Install Azure Data Studio via Snap (more reliable than direct download)
echo "Installing Azure Data Studio via Snap..."
apt-get install -y snapd
# Ensure snapd is running
systemctl enable snapd
systemctl start snapd
sleep 2

# Install Azure Data Studio via snap
snap install azuredatastudio || {
    echo "Failed to install via snap, trying alternative method..."
    # Fallback to direct .deb download
    cd /tmp
    wget -O azuredatastudio.deb "https://azuredatastudio-update.azurewebsites.net/latest/linux-deb-x64/stable" 2>&1 || true
    if [ -f azuredatastudio.deb ] && [ -s azuredatastudio.deb ]; then
        dpkg -i azuredatastudio.deb || apt-get install -f -y
    fi
    rm -f azuredatastudio.deb
}

# Install SQL command-line tools (sqlcmd)
echo "Installing SQL command-line tools..."
# Add Microsoft repository for mssql-tools
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
curl -fsSL https://packages.microsoft.com/config/ubuntu/22.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list

apt-get update

# Install mssql-tools18 (accepts EULA automatically)
ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev || {
    echo "Warning: Could not install mssql-tools18, continuing without CLI tools"
}

# Add sqlcmd to PATH for all users
if [ -d /opt/mssql-tools18/bin ]; then
    echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> /etc/profile.d/mssql-tools.sh
    chmod +x /etc/profile.d/mssql-tools.sh
fi

# Install Python packages for verification scripts
echo "Installing Python packages..."
apt-get install -y python3-pip
pip3 install --no-cache-dir --break-system-packages pyodbc pymssql || \
pip3 install --no-cache-dir pyodbc pymssql || true

# Pull SQL Server Docker image ahead of time (speeds up post_start)
echo "Pulling SQL Server 2022 Docker image..."
docker pull mcr.microsoft.com/mssql/server:2022-latest || {
    echo "Warning: Could not pre-pull SQL Server image, will download during setup"
}

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Verify installations
echo ""
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Azure Data Studio: $(which azuredatastudio 2>/dev/null || snap list azuredatastudio 2>/dev/null | tail -1 || echo 'not found')"
if command -v sqlcmd &> /dev/null; then
    echo "sqlcmd: $(which sqlcmd)"
fi
echo ""
echo "SQL Server will be started via Docker in post_start hook"
