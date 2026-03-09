#!/bin/bash
set -euo pipefail

echo "=== Installing ProjectLibre and dependencies ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java runtime (ProjectLibre requires JRE)
echo "Installing Java runtime..."
apt-get install -y \
    default-jre \
    default-jdk-headless

# Install GUI automation and utility tools
echo "Installing GUI automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    x11-xserver-utils \
    xclip \
    scrot \
    imagemagick \
    unzip \
    zip \
    curl \
    wget \
    jq \
    python3-pip \
    python3-dev \
    libxml2-utils \
    xmlstarlet \
    cups \
    cups-pdf

# Install Python libraries for verification
echo "Installing Python libraries..."
pip3 install --no-cache-dir \
    pillow \
    lxml

# Download and install ProjectLibre .deb package
echo "Downloading ProjectLibre 1.9.3..."
PROJECTLIBRE_VERSION="1.9.3"
PROJECTLIBRE_DEB="projectlibre_${PROJECTLIBRE_VERSION}-1.deb"

# Primary download: SourceForge CDN (no JS redirect)
wget -L --no-check-certificate -q --show-progress \
    "https://downloads.sourceforge.net/project/projectlibre/ProjectLibre/${PROJECTLIBRE_VERSION}/${PROJECTLIBRE_DEB}" \
    -O /tmp/projectlibre.deb 2>/dev/null && DOWNLOAD_OK=true || DOWNLOAD_OK=false

# Fallback: SourceForge download page with redirect
if [ "$DOWNLOAD_OK" = "false" ]; then
    echo "Primary download failed, trying fallback..."
    wget -L --no-check-certificate -q --show-progress \
        "https://sourceforge.net/projects/projectlibre/files/ProjectLibre/${PROJECTLIBRE_VERSION}/${PROJECTLIBRE_DEB}/download" \
        -O /tmp/projectlibre.deb 2>/dev/null && DOWNLOAD_OK=true || DOWNLOAD_OK=false
fi

# Second fallback: version 1.9.1
if [ "$DOWNLOAD_OK" = "false" ]; then
    echo "Trying version 1.9.1..."
    wget -L --no-check-certificate -q --show-progress \
        "https://downloads.sourceforge.net/project/projectlibre/ProjectLibre/1.9.1/projectlibre_1.9.1-1.deb" \
        -O /tmp/projectlibre.deb 2>/dev/null && DOWNLOAD_OK=true || DOWNLOAD_OK=false
fi

if [ "$DOWNLOAD_OK" = "false" ]; then
    echo "ERROR: All download attempts failed for ProjectLibre"
    exit 1
fi

# Verify the download is a valid deb package
FILE_TYPE=$(file /tmp/projectlibre.deb)
echo "Downloaded file type: $FILE_TYPE"
if ! echo "$FILE_TYPE" | grep -qi "debian\|deb\|ar\|archive"; then
    echo "WARNING: Downloaded file may not be a valid .deb package"
    ls -la /tmp/projectlibre.deb
fi

# Install ProjectLibre
echo "Installing ProjectLibre package..."
dpkg -i /tmp/projectlibre.deb || true
# Fix any missing dependencies
apt-get install -f -y
rm -f /tmp/projectlibre.deb

# Verify installation
echo "Verifying ProjectLibre installation..."
if command -v projectlibre > /dev/null 2>&1; then
    echo "ProjectLibre command found: $(which projectlibre)"
else
    # Check alternative locations
    PROJECTLIBRE_BIN=$(find /usr /opt /usr/share -name "projectlibre" -type f 2>/dev/null | head -1)
    if [ -n "$PROJECTLIBRE_BIN" ]; then
        echo "ProjectLibre found at: $PROJECTLIBRE_BIN"
        ln -sf "$PROJECTLIBRE_BIN" /usr/local/bin/projectlibre 2>/dev/null || true
    else
        # Check for jar file
        PROJECTLIBRE_JAR=$(find /usr /opt /usr/share -name "projectlibre*.jar" 2>/dev/null | head -1)
        if [ -n "$PROJECTLIBRE_JAR" ]; then
            echo "ProjectLibre JAR found at: $PROJECTLIBRE_JAR"
            # Create wrapper script
            cat > /usr/local/bin/projectlibre << WRAPPER
#!/bin/bash
java -jar "$PROJECTLIBRE_JAR" "\$@"
WRAPPER
            chmod +x /usr/local/bin/projectlibre
        else
            echo "ERROR: ProjectLibre installation could not be verified"
            find /usr /opt /usr/share -name "*projectlibre*" 2>/dev/null | head -10
            exit 1
        fi
    fi
fi

# Install cups-pdf for PDF export capability
echo "Configuring CUPS for PDF printing..."
systemctl enable cups 2>/dev/null || true

# Clean up package cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== ProjectLibre installation complete ==="
echo "ProjectLibre version details:"
dpkg -l projectlibre 2>/dev/null || echo "(package info via dpkg not available)"
