#!/bin/bash
set -e

echo "=== Installing Portfolio Performance ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java 21 (required by Portfolio Performance 0.81.x)
apt-get install -y openjdk-21-jre-headless

# Install GUI automation and utility tools
apt-get install -y \
    xdotool wmctrl x11-utils imagemagick \
    wget curl jq unzip \
    python3-pip \
    libgtk-3-0 libwebkit2gtk-4.0-37 libswt-gtk-4-java

# Download Portfolio Performance v0.81.5 for Linux x86_64
PP_VERSION="0.81.5"
PP_URL="https://github.com/portfolio-performance/portfolio/releases/download/${PP_VERSION}/PortfolioPerformance-${PP_VERSION}-linux.gtk.x86_64.tar.gz"
PP_FALLBACK_URL="https://github.com/buchen/portfolio/releases/download/${PP_VERSION}/PortfolioPerformance-${PP_VERSION}-linux.gtk.x86_64.tar.gz"

echo "Downloading Portfolio Performance v${PP_VERSION}..."
mkdir -p /opt/portfolio-performance

wget -q -O /tmp/pp.tar.gz "$PP_URL" || \
    wget -q -O /tmp/pp.tar.gz "$PP_FALLBACK_URL" || \
    { echo "ERROR: Failed to download Portfolio Performance"; exit 1; }

# Extract to /opt/portfolio-performance
tar -xzf /tmp/pp.tar.gz -C /opt/portfolio-performance --strip-components=1

# Verify the executable exists
if [ ! -f /opt/portfolio-performance/PortfolioPerformance ]; then
    echo "ERROR: PortfolioPerformance executable not found after extraction"
    ls -la /opt/portfolio-performance/
    exit 1
fi

# Make executable
chmod +x /opt/portfolio-performance/PortfolioPerformance

# Create symlink for easy access
ln -sf /opt/portfolio-performance/PortfolioPerformance /usr/local/bin/portfolio-performance

# Create desktop entry
mkdir -p /usr/share/applications
cat > /usr/share/applications/portfolio-performance.desktop << 'EOF'
[Desktop Entry]
Name=Portfolio Performance
Comment=Track and evaluate investment portfolio performance
Exec=/opt/portfolio-performance/PortfolioPerformance
Icon=/opt/portfolio-performance/icon.xpm
Type=Application
Categories=Office;Finance;
Terminal=false
EOF

# Copy real data files to accessible location
mkdir -p /home/ga/Documents/PortfolioData
cp -r /workspace/data/* /home/ga/Documents/PortfolioData/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents

# Clean up
rm -f /tmp/pp.tar.gz
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Portfolio Performance v${PP_VERSION} installation complete ==="
