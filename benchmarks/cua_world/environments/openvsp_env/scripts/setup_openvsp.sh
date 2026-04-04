#!/bin/bash
set -e

echo "=== Setting up OpenVSP ==="

# Wait for desktop to be ready
sleep 5

# Create working directories
mkdir -p /home/ga/Documents/OpenVSP
mkdir -p /home/ga/Documents/OpenVSP/exports
mkdir -p /home/ga/Desktop

# Copy real aircraft model files to user workspace
cp /opt/openvsp_models/*.vsp3 /home/ga/Documents/OpenVSP/ 2>/dev/null || \
    cp /workspace/data/*.vsp3 /home/ga/Documents/OpenVSP/ 2>/dev/null || true

chown -R ga:ga /home/ga/Documents/OpenVSP
chown -R ga:ga /home/ga/Desktop

# Find the OpenVSP binary
VSPBIN=""
for candidate in /usr/local/bin/openvsp /usr/bin/vsp /usr/local/bin/vsp /opt/OpenVSP/vsp; do
    if [ -x "$candidate" ]; then
        VSPBIN="$candidate"
        break
    fi
done

# Broader search if not found
if [ -z "$VSPBIN" ]; then
    VSPBIN=$(find /usr /opt -name "vsp" -type f -executable 2>/dev/null | head -1)
fi

if [ -z "$VSPBIN" ]; then
    echo "ERROR: Cannot find OpenVSP binary"
    exit 1
fi

echo "Using OpenVSP binary: $VSPBIN"

# Create desktop launcher script
cat > /home/ga/Desktop/launch_openvsp.sh << LAUNCHEOF
#!/bin/bash
export DISPLAY=:1
cd /home/ga/Documents/OpenVSP
$VSPBIN "\$@" &
LAUNCHEOF
chmod +x /home/ga/Desktop/launch_openvsp.sh
chown ga:ga /home/ga/Desktop/launch_openvsp.sh

# Create .desktop file
cat > /home/ga/Desktop/OpenVSP.desktop << DESKTOPEOF
[Desktop Entry]
Type=Application
Name=OpenVSP
Exec=$VSPBIN
Icon=applications-engineering
Terminal=false
Categories=Engineering;Science;
DESKTOPEOF
chmod +x /home/ga/Desktop/OpenVSP.desktop
chown ga:ga /home/ga/Desktop/OpenVSP.desktop

# Store the binary path for task scripts
echo "$VSPBIN" > /tmp/openvsp_bin_path

# Warm-up launch to clear any first-run dialogs
echo "Performing warm-up launch..."
su - ga -c "DISPLAY=:1 setsid $VSPBIN > /tmp/openvsp_warmup.log 2>&1 &"

# Wait for window to appear
WARMUP_TIMEOUT=60
WARMUP_ELAPSED=0
WARMUP_WID=""
while [ $WARMUP_ELAPSED -lt $WARMUP_TIMEOUT ]; do
    # Title format: "OpenVSP 3.X.X - MM/DD/YY     filename.vsp3"
    WARMUP_WID=$(DISPLAY=:1 xdotool search --name "OpenVSP" 2>/dev/null | head -1)
    if [ -n "$WARMUP_WID" ]; then
        echo "OpenVSP warm-up window appeared after ${WARMUP_ELAPSED}s"
        break
    fi
    sleep 2
    WARMUP_ELAPSED=$((WARMUP_ELAPSED + 2))
done

if [ -n "$WARMUP_WID" ]; then
    # Dismiss any dialogs
    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 2
    echo "Warm-up complete, closing OpenVSP"
else
    echo "WARNING: OpenVSP window did not appear during warm-up"
fi

# Kill warm-up instance
pkill -f "$VSPBIN" 2>/dev/null || true
sleep 2
pkill -9 -f "$VSPBIN" 2>/dev/null || true

# Verify files are in place
echo "Aircraft model files:"
ls -la /home/ga/Documents/OpenVSP/*.vsp3 2>/dev/null || echo "No .vsp3 files found"

echo "=== OpenVSP setup complete ==="
