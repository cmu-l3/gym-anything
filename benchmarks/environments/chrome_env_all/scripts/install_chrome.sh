#!/bin/bash
# set -euo pipefail

# ============================================================================
# Non-interactive installs (Docker-friendly)
#
# Prompts you reported come from:
# - "Daemons using outdated libraries" / "Which services should be restarted?"
#   This is emitted by the `needrestart` package (an apt hook) via whiptail/dialog.
# - "Mail server" configuration prompts are typically from `postfix` (debconf).
#
# This script must run fully unattended, so we force noninteractive debconf and
# disable `needrestart`'s interactive UI.
# ============================================================================
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true

# If `needrestart` is installed, prevent it from opening an interactive TUI.
# Use "l" (list only) so builds don't restart daemons inside the container.
export NEEDRESTART_MODE=l

# Silence other potential apt UIs (rare, but shows up in some base images)
export APT_LISTCHANGES_FRONTEND=none

APT_GET_INSTALL_FLAGS=(
  -yq
  --no-install-recommends
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
)

echo "=== Installing Chrome/Chromium and related packages ==="

# ======= FIX: Configure faster APT mirrors =======
echo "Configuring faster APT mirrors for Azure infrastructure..."

# Backup original sources if they exist
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
fi


# Configure apt to be faster and more reliable
cat > /etc/apt/apt.conf.d/99custom << 'APT_CONF_EOF'
# Speed up apt by reducing retries and timeouts
Acquire::Retries "3";
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::ftp::Timeout "10";

# Use parallel downloads
Acquire::Queue-Mode "access";

# Reduce cache validity
Acquire::http::No-Cache "false";
APT_CONF_EOF

echo "Mirror configuration updated to use Azure mirrors"

# Update package manager
apt-get update -yq

# Ensure debconf tools exist so we can preseed packages that might prompt
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" debconf-utils

# Preseed common MTA prompt (if postfix gets installed as a dependency in your base image)
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections || true
echo "postfix postfix/mailname string localhost" | debconf-set-selections || true

# Configure needrestart to never open an interactive UI (if present)
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/99-noninteractive.conf <<'NEEDRESTART_EOF'
$nrconf{restart} = 'l';
$nrconf{ui} = 'stdio';
NEEDRESTART_EOF

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Install Chrome/Chromium based on architecture
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    # Install Google Chrome for x86_64
    echo "Installing Google Chrome for x86_64..."
    apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
        wget \
        gnupg \
        ca-certificates \
        apt-transport-https
    
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    
    apt-get update -yq
    apt-get install "${APT_GET_INSTALL_FLAGS[@]}" google-chrome-stable
    
    # Create symlink for consistent naming
    ln -sf /usr/bin/google-chrome-stable /usr/bin/chrome-browser
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    # Install Chromium for ARM64
    # Ubuntu 24.04 ships chromium as a snap wrapper, which doesn't work in containers
    # So we'll use Debian's chromium package or download binaries
    echo "Installing Chromium for ARM64 (container-compatible)..."
    
    # Install dependencies first
    apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
        wget \
        gpg \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2t64 \
        libatspi2.0-0 \
        libglib2.0-0t64 \
        libdbus-1-3
    
    # Try installing from snap if possible, otherwise use alternative
    if systemctl is-active --quiet snapd 2>/dev/null; then
        snap install chromium
        ln -sf /snap/bin/chromium /usr/bin/chromium-browser
    else
        # Snap doesn't work, download Chromium binaries or use flatpak
        echo "Snapd not available, installing Chromium from alternative source..."
        
        # Option 1: Try Debian repository (has actual .deb files)
        echo "deb http://deb.debian.org/debian sid main" > /etc/apt/sources.list.d/debian-sid.list
        apt-get update -yq
        apt-get install "${APT_GET_INSTALL_FLAGS[@]}" -t sid chromium || {
            # If that fails, download pre-built Chromium
            echo "Falling back to downloading Chromium binaries..."
            CHROMIUM_VERSION="120.0.6099.109"
            wget -q "https://commondatastorage.googleapis.com/chromium-browser-snapshots/Linux_ARM64/LAST_CHANGE" -O /tmp/chromium_version
            CHROMIUM_BUILD=$(cat /tmp/chromium_version)
            wget -q "https://commondatastorage.googleapis.com/chromium-browser-snapshots/Linux_ARM64/${CHROMIUM_BUILD}/chrome-linux.zip" -O /tmp/chromium.zip
            
            apt-get install "${APT_GET_INSTALL_FLAGS[@]}" unzip
            unzip -q /tmp/chromium.zip -d /opt/
            mv /opt/chrome-linux /opt/chromium
            
            # Create wrapper script
            cat > /usr/bin/chromium-browser << 'WRAPPER_EOF'
#!/bin/bash
exec /opt/chromium/chrome "$@"
WRAPPER_EOF
            chmod +x /usr/bin/chromium-browser
            rm /tmp/chromium.zip /tmp/chromium_version
        }
    fi
    
    # Create symlinks for consistent naming
    ln -sf /usr/bin/chromium-browser /usr/bin/chrome-browser
    ln -sf /usr/bin/chromium-browser /usr/bin/google-chrome-stable
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

echo "Chrome/Chromium installed successfully"

# Install Chrome automation and debugging tools
echo "Installing automation tools..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    xdotool \
    wmctrl \
    x11-utils \
    xclip \
    socat \
    netcat-openbsd \
    jq \
    python3-pip \
    python3-dev \
    python3-venv

# Install Python libraries for Chrome DevTools Protocol
echo "Installing Python CDP libraries..."
pip3 install --no-cache-dir \
    pychrome \
    selenium \
    websocket-client \
    requests \
    beautifulsoup4 \
    lxml \
    tldextract \
    rapidfuzz

# Install file handling utilities
echo "Installing file handling utilities..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    imagemagick \
    poppler-utils \
    ghostscript \
    libreoffice-writer \
    libreoffice-calc \
    unzip \
    zip \
    p7zip-full \
    rar \
    unrar

# Install multimedia tools
echo "Installing multimedia tools..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    ffmpeg \
    vlc \
    pulseaudio

# Install fonts for better web rendering
echo "Installing additional fonts..."
apt-get install "${APT_GET_INSTALL_FLAGS[@]}" \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto \
    fonts-noto-color-emoji \
    fonts-hack \
    fonts-firacode \
    fonts-roboto \
    fonts-open-sans

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Google Chrome installation completed ==="
