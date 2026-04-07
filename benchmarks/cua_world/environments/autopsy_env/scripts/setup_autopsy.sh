#!/bin/bash
# Do NOT use set -e — let commands fail gracefully
echo "=== Setting up Autopsy environment ==="

# Wait for desktop to be ready
sleep 5

# Find Autopsy installation directory
AUTOPSY_DIR=$(find /opt -maxdepth 1 -type d -name 'autopsy*' 2>/dev/null | head -1)
if [ -z "$AUTOPSY_DIR" ]; then
    echo "WARNING: Autopsy directory not found in /opt/"
    echo "=== Setup skipped ==="
    exit 0
fi

echo "Autopsy directory: $AUTOPSY_DIR"

# ============================================================
# Create Autopsy desktop launcher
# ============================================================
cat > /home/ga/Desktop/Autopsy.desktop << EOF
[Desktop Entry]
Name=Autopsy
Comment=Digital Forensics Platform
Exec=$AUTOPSY_DIR/bin/autopsy
Icon=autopsy
Terminal=false
Type=Application
Categories=System;Utility;
EOF
chown ga:ga /home/ga/Desktop/Autopsy.desktop 2>/dev/null || true
chmod +x /home/ga/Desktop/Autopsy.desktop 2>/dev/null || true

# Create convenience symlink to evidence directory on Desktop
ln -sf /home/ga/evidence /home/ga/Desktop/evidence 2>/dev/null || true

# ============================================================
# Configure Autopsy user preferences to suppress dialogs
# ============================================================
AUTOPSY_CONFIG_DIR="/home/ga/.autopsy/dev/config"
mkdir -p "$AUTOPSY_CONFIG_DIR"

cat > "$AUTOPSY_CONFIG_DIR/Preferences.properties" << 'EOF'
UpdateNotification.autoCheck=false
UpdateNotification.lastCheck=-1
ShowWelcome=true
EOF

# Create case output directory
mkdir -p /home/ga/Cases

# Set default case directory
cat > "$AUTOPSY_CONFIG_DIR/Case.properties" << 'EOF'
CasesRootFolder=/home/ga/Cases
EOF

chown -R ga:ga /home/ga/.autopsy 2>/dev/null || true
chown -R ga:ga /home/ga/Cases 2>/dev/null || true

# ============================================================
# Limit Autopsy JVM memory to prevent OOM
# ============================================================
AUTOPSY_CONF="$AUTOPSY_DIR/etc/autopsy.conf"
if [ -f "$AUTOPSY_CONF" ]; then
    # Reduce max heap to prevent OOM. Replace existing -Xmx values
    sed -i 's/-J-Xmx[0-9]*[gGmM]/-J-Xmx2g/g' "$AUTOPSY_CONF" 2>/dev/null || true
    # If -Xmx not present, add it to default_options
    if ! grep -q '\-J-Xmx' "$AUTOPSY_CONF" 2>/dev/null; then
        sed -i 's/^default_options="/default_options="-J-Xmx2g -J-Xms256m /' "$AUTOPSY_CONF" 2>/dev/null || true
    fi
    echo "Autopsy JVM memory limited to 2g"
    echo "autopsy.conf content:"
    cat "$AUTOPSY_CONF" 2>/dev/null || true
fi

# ============================================================
# Set environment variables for ga user
# ============================================================
JAVA_HOME=$(find /usr/lib/jvm -maxdepth 1 -type d -name 'java-17*' 2>/dev/null | head -1)

cat >> /home/ga/.bashrc << EOF

# Autopsy environment
export DISPLAY=:1
export JAVA_HOME=$JAVA_HOME
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF

# ============================================================
# Warm-up launch: initialize Autopsy caches so pre_task is fast
# First launch takes 3-5 min (module loading, Solr init, etc.)
# Subsequent launches take ~30s with warm caches.
# ============================================================
echo "Warm-up launch: initializing Autopsy caches..."

su - ga -c "DISPLAY=:1 JAVA_HOME=$JAVA_HOME setsid $AUTOPSY_DIR/bin/autopsy -J-Xmx2g -J-Xms256m > /tmp/autopsy_warmup.log 2>&1 &"

# Wait for module loading to complete by checking the autopsy log
WARMUP_TIMEOUT=360
WARMUP_ELAPSED=0
while [ $WARMUP_ELAPSED -lt $WARMUP_TIMEOUT ]; do
    # Check if autopsy.log shows modules finished restoring
    if grep -q "ingest.Installer restore succeeded" /home/ga/.autopsy/dev/var/log/autopsy.log.0 2>/dev/null; then
        echo "Warm-up: modules loaded after ${WARMUP_ELAPSED}s"
        break
    fi
    # Also click to nudge splash screen
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    sleep 10
    WARMUP_ELAPSED=$((WARMUP_ELAPSED + 10))
done

# Wait a bit more for any remaining initialization
sleep 5

# Kill Autopsy after warm-up (including Solr child processes)
pkill -f "/opt/autopsy" 2>/dev/null || true
sleep 3
pkill -9 -f "/opt/autopsy" 2>/dev/null || true
pkill -9 -f "java.*netbeans" 2>/dev/null || true
# Kill any lingering Solr processes started by Autopsy
pkill -9 -f "solr" 2>/dev/null || true
sleep 2

# Clean up Solr lock files and temp state left from warm-up
# This prevents "Unable to connect to Solr server null" on next launch
rm -rf /home/ga/.autopsy/dev/var/cache/* 2>/dev/null || true
rm -f /home/ga/.autopsy/dev/var/log/autopsy.log.0.lck 2>/dev/null || true
# Remove any Solr core data from warm-up (no case was created, but Solr may have temp state)
find /home/ga/.autopsy -name "write.lock" -delete 2>/dev/null || true

echo "Warm-up complete. Caches initialized. Solr state cleaned."
echo "Memory after warm-up:"
free -h 2>/dev/null | head -2

# ============================================================
# Verify setup
# ============================================================
echo "Verifying Autopsy setup..."

[ -x "$AUTOPSY_DIR/bin/autopsy" ] && echo "  Autopsy binary: OK" || echo "  WARNING: Autopsy binary missing"

echo "  Evidence files:"
ls -la /home/ga/evidence/ 2>/dev/null || echo "  No evidence files"

[ -d "$AUTOPSY_CONFIG_DIR" ] && echo "  Config: OK" || echo "  Config: missing"

echo "Disk space:"
df -h / 2>/dev/null || true

echo "Memory:"
free -h 2>/dev/null || true

echo "=== Autopsy setup complete ==="
