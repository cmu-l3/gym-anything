#!/bin/bash
# pre_start hook — install Floreant POS and dependencies
# Runs as root before the desktop starts

echo "=== Installing Floreant POS ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Java (OpenJDK 11 — best compatibility with Floreant's Java Swing UI)
echo "Installing Java..."
apt-get install -y openjdk-11-jre openjdk-11-jdk

# Install GUI automation and utility tools
echo "Installing GUI tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    x11-utils \
    scrot \
    imagemagick \
    wget \
    unzip \
    python3-pip \
    net-tools \
    curl

# Install fonts (Floreant POS UI needs decent font rendering)
apt-get install -y \
    fonts-liberation \
    fonts-dejavu-extra \
    fonts-noto

# Download Floreant POS 1.4 build 1707b from SourceForge
echo "Downloading Floreant POS..."
DOWNLOAD_URL="https://sourceforge.net/projects/floreantpos/files/floreantpos-1.4-build1707b.zip/download"
DEST="/tmp/floreantpos.zip"

wget -q --no-check-certificate \
     --tries=3 \
     --timeout=120 \
     -O "$DEST" \
     "$DOWNLOAD_URL"

if [ ! -f "$DEST" ] || [ ! -s "$DEST" ]; then
    echo "Primary download failed, trying alternative..."
    # Fallback: try direct SourceForge mirror
    wget -q --no-check-certificate \
         --tries=3 \
         --timeout=120 \
         -O "$DEST" \
         "https://downloads.sourceforge.net/project/floreantpos/floreantpos-1.4-build1707b.zip"
fi

if [ ! -f "$DEST" ] || [ ! -s "$DEST" ]; then
    echo "ERROR: Could not download Floreant POS"
    exit 1
fi

echo "Download complete: $(du -sh $DEST | cut -f1)"

# Extract to /opt/floreantpos
echo "Extracting Floreant POS..."
mkdir -p /opt/floreantpos
# Use -qo flags: quiet, overwrite without prompting
unzip -qo "$DEST" -d /opt/floreantpos/
rm -f "$DEST"

# Find the actual extracted directory (it may be nested)
EXTRACTED_DIR=$(find /opt/floreantpos -maxdepth 1 -type d | grep -v "^/opt/floreantpos$" | head -1)
if [ -n "$EXTRACTED_DIR" ] && [ "$EXTRACTED_DIR" != "/opt/floreantpos" ]; then
    echo "Moving contents from $EXTRACTED_DIR to /opt/floreantpos..."
    mv "$EXTRACTED_DIR"/* /opt/floreantpos/ 2>/dev/null || true
    rmdir "$EXTRACTED_DIR" 2>/dev/null || true
fi

# Verify jar exists — look specifically for floreantpos.jar in root dir
# The archive ships with floreantpos.jar (main app) in the root and lib/ for dependencies
JAR="/opt/floreantpos/floreantpos.jar"
if [ ! -f "$JAR" ]; then
    # Fallback: search for it
    JAR=$(find /opt/floreantpos -maxdepth 1 -name "floreantpos.jar" | head -1)
fi

if [ -z "$JAR" ] || [ ! -f "$JAR" ]; then
    echo "ERROR: Could not find floreantpos.jar"
    ls -la /opt/floreantpos/
    exit 1
fi

echo "Found JAR: $JAR"

# Create launcher script — sets DISPLAY internally so setsid + su chain works
# (setsid requires the command to be a real binary, not an env var assignment)
cat > /usr/local/bin/floreant-pos << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
cd /opt/floreantpos
exec java \
    -Xmx512m \
    -Djava.awt.headless=false \
    -Dfile.encoding=UTF-8 \
    -jar /opt/floreantpos/floreantpos.jar \
    "$@"
LAUNCHEOF
chmod +x /usr/local/bin/floreant-pos

# Set permissions so ga user can write the Derby database
chown -R ga:ga /opt/floreantpos/
chmod -R 755 /opt/floreantpos/

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Floreant POS installation complete ==="
echo "JAR: $JAR"
echo "Launch with: floreant-pos"
