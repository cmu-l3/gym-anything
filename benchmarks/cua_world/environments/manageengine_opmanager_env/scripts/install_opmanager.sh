#!/bin/bash
# ManageEngine OpManager Installation Script (pre_start hook)
# Downloads and installs OpManager with bundled PostgreSQL and JRE
set -e

echo "=== Installing ManageEngine OpManager ==="

# Configure non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# ============================================================
# 1. Update package lists and install system dependencies
# ============================================================
echo "Updating package lists..."
apt-get update

echo "Installing system dependencies..."
apt-get install -y \
    wget \
    curl \
    jq \
    net-tools \
    lsof \
    unzip \
    libxtst6 \
    libxi6 \
    libxrender1 \
    libfontconfig1 \
    libxext6 \
    libx11-6

# ============================================================
# 2. Install SNMP agent for real network monitoring data
# ============================================================
echo "Installing SNMP agent and tools..."
apt-get install -y \
    snmpd \
    snmp || true

# snmp-mibs-downloader may not be available in all repos
apt-get install -y snmp-mibs-downloader 2>/dev/null || true

# Configure SNMP agent with real system data
cp /workspace/config/snmpd.conf /etc/snmp/snmpd.conf

# Enable SNMP to listen on all interfaces
sed -i 's/^agentaddress.*/agentaddress udp:161/' /etc/snmp/snmpd.conf 2>/dev/null || true
# Also ensure agentaddress is set if not present
if ! grep -q '^agentaddress' /etc/snmp/snmpd.conf; then
    echo "agentaddress udp:161" >> /etc/snmp/snmpd.conf
fi

# Enable MIBs (Ubuntu disables them by default)
sed -i 's/^mibs :$/# mibs :/' /etc/snmp/snmp.conf 2>/dev/null || true

systemctl enable snmpd
systemctl start snmpd

# Verify SNMP is working
echo "Verifying SNMP agent..."
snmpwalk -v2c -c public 127.0.0.1 system 2>/dev/null | head -5 || echo "SNMP verification will complete after full boot"

# ============================================================
# 3. Install Firefox and GUI automation tools
# ============================================================
echo "Installing Firefox and automation tools..."
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    imagemagick

# scrot may not be available in all repos
apt-get install -y scrot 2>/dev/null || true

# ============================================================
# 4. Download ManageEngine OpManager
# ============================================================
echo "Downloading ManageEngine OpManager..."
OPMANAGER_DIR="/opt/ManageEngine/OpManager"
INSTALLER="/tmp/ManageEngine_OpManager_64bit.bin"

# Try multiple download URLs (cross-cutting pattern #7: fragile URLs)
DOWNLOAD_URLS=(
    "https://www.manageengine.com/network-monitoring/29809517/ManageEngine_OpManager_64bit.bin"
    "https://download.manageengine.com/network-monitoring/ManageEngine_OpManager_64bit.bin"
    "https://archives.manageengine.com/opmanager/ManageEngine_OpManager_64bit.bin"
)

DOWNLOAD_SUCCESS=false
for url in "${DOWNLOAD_URLS[@]}"; do
    echo "Trying download from: $url"
    if wget --timeout=120 --tries=3 -q --show-progress -O "$INSTALLER" "$url" 2>&1; then
        # Verify file is actually a binary (not an HTML error page)
        FILE_SIZE=$(stat -c%s "$INSTALLER" 2>/dev/null || echo "0")
        if [ "$FILE_SIZE" -gt 100000000 ]; then
            echo "Download successful (${FILE_SIZE} bytes)"
            DOWNLOAD_SUCCESS=true
            break
        else
            echo "Downloaded file too small (${FILE_SIZE} bytes), likely error page"
            rm -f "$INSTALLER"
        fi
    else
        echo "Download failed from $url"
        rm -f "$INSTALLER"
    fi
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "ERROR: Could not download OpManager from any URL"
    echo "Attempting alternative approach via ManageEngine download page..."

    # Try to get the latest download URL from the download page
    DOWNLOAD_PAGE=$(curl -sL "https://www.manageengine.com/network-monitoring/download.html" 2>/dev/null)
    EXTRACTED_URL=$(echo "$DOWNLOAD_PAGE" | grep -oP 'https://[^"]*ManageEngine_OpManager_64bit\.bin' | head -1)

    if [ -n "$EXTRACTED_URL" ]; then
        echo "Found URL from download page: $EXTRACTED_URL"
        wget --timeout=120 --tries=3 -q --show-progress -O "$INSTALLER" "$EXTRACTED_URL" 2>&1
        FILE_SIZE=$(stat -c%s "$INSTALLER" 2>/dev/null || echo "0")
        if [ "$FILE_SIZE" -gt 100000000 ]; then
            DOWNLOAD_SUCCESS=true
        fi
    fi

    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        echo "FATAL: Unable to download OpManager installer"
        exit 1
    fi
fi

# ============================================================
# 5. Install ManageEngine OpManager (silent mode)
# ============================================================
echo "Installing ManageEngine OpManager (this may take several minutes)..."
chmod a+x "$INSTALLER"

# Run installer in silent mode with default settings
# InstallAnywhere silent install: -i silent, -DUSER_INSTALL_DIR sets install path
"$INSTALLER" -i silent \
    -DUSER_INSTALL_DIR="$OPMANAGER_DIR" \
    2>&1 || {
    echo "Silent install returned non-zero exit code, checking if installation succeeded..."
}

# Verify installation
if [ -d "$OPMANAGER_DIR" ] && [ -f "$OPMANAGER_DIR/bin/run.sh" ]; then
    echo "OpManager installed successfully at $OPMANAGER_DIR"
else
    echo "Silent install may have failed, trying console mode..."
    # Fallback: console mode with piped answers
    # Answers: Enter (accept license) -> 3 (Free Edition) -> Enter (default dir) -> Enter (port 8060) -> Enter (port 8061) -> Enter (skip name) -> Enter (skip email)
    echo -e "\n\n3\n\n\n\n\n\n\n\ny\n" | "$INSTALLER" -i console 2>&1 || true

    if [ -d "$OPMANAGER_DIR" ] && [ -f "$OPMANAGER_DIR/bin/run.sh" ]; then
        echo "OpManager installed successfully via console mode"
    else
        # Check alternate install locations
        for alt_dir in /opt/ManageEngine/OpManager /home/ga/ManageEngine/OpManager /ManageEngine/OpManager; do
            if [ -d "$alt_dir" ] && [ -f "$alt_dir/bin/run.sh" ]; then
                OPMANAGER_DIR="$alt_dir"
                echo "OpManager found at alternate location: $OPMANAGER_DIR"
                break
            fi
        done

        if [ ! -d "$OPMANAGER_DIR" ] || [ ! -f "$OPMANAGER_DIR/bin/run.sh" ]; then
            echo "FATAL: OpManager installation failed"
            ls -la /opt/ManageEngine/ 2>/dev/null || echo "/opt/ManageEngine/ does not exist"
            exit 1
        fi
    fi
fi

# ============================================================
# 6. Fix port placeholders in server.xml
# ============================================================
echo "Fixing web server port configuration..."
# The silent installer leaves HTTP_PORT/WEBSERVER_PORT as placeholders
# Replace them with actual port numbers
if [ -f "$OPMANAGER_DIR/conf/server.xml" ]; then
    python3 -c "
with open('$OPMANAGER_DIR/conf/server.xml', 'r') as f:
    content = f.read()
content = content.replace('HTTP_PORT', '8060')
content = content.replace('WEBSERVER_PORT', '8443')
with open('$OPMANAGER_DIR/conf/server.xml', 'w') as f:
    f.write(content)
print('Port placeholders fixed: HTTP_PORT->8060, WEBSERVER_PORT->8443')
"
fi

# ============================================================
# 7. Register OpManager as a systemd service
# ============================================================
echo "Registering OpManager as systemd service..."

# Remove any masked service from linkAsService.sh (it creates broken configs)
systemctl unmask OpManager.service 2>/dev/null || true
rm -f /etc/systemd/system/OpManager.service 2>/dev/null || true

# Create a clean systemd service file
# CRITICAL: WorkingDirectory must be the bin/ dir because run.sh uses relative paths
cat > /etc/systemd/system/OpManager.service << EOF
[Unit]
Description=ManageEngine OpManager
After=network.target

[Service]
Type=simple
WorkingDirectory=$OPMANAGER_DIR/bin
ExecStart=$OPMANAGER_DIR/bin/run.sh
ExecStop=$OPMANAGER_DIR/bin/shutdown.sh
Restart=on-failure
RestartSec=10
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable OpManager.service 2>/dev/null || true

# ============================================================
# 8. Store installation info and clean up
# ============================================================
echo "$OPMANAGER_DIR" > /tmp/opmanager_install_dir

# Clean up installer to save disk space
rm -f "$INSTALLER"

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== ManageEngine OpManager Installation Complete ==="
echo "Install directory: $OPMANAGER_DIR"
echo "SNMP agent: $(systemctl is-active snmpd 2>/dev/null || echo 'installed')"
echo "Firefox: $(which firefox)"
echo ""
echo "OpManager will be started and configured in post_start hook"
