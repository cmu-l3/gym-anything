#!/bin/bash
set -e

echo "=== Setting up NASA Panoply environment ==="

# Wait for desktop to be ready
sleep 5

# Create directories
DATA_DIR="/home/ga/PanoplyData"
CONFIG_DIR="/home/ga/.panoply"
mkdir -p "$DATA_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Documents/PanoplyExports

# Verify data files exist
echo "Checking data files..."
for f in air.mon.ltm.nc sst.ltm.1991-2020.nc prate.sfc.mon.ltm.nc slp.mon.ltm.nc pres.mon.ltm.nc; do
    if [ -f "$DATA_DIR/$f" ]; then
        echo "  Found: $f ($(stat -c%s "$DATA_DIR/$f" 2>/dev/null || echo '?') bytes)"
    else
        echo "  Missing: $f"
    fi
done

# Create desktop launcher
cat > /home/ga/Desktop/Panoply.desktop << 'EOF'
[Desktop Entry]
Name=Panoply
GenericName=NetCDF Data Viewer
Comment=NASA Panoply - View netCDF, HDF, GRIB data
Exec=/opt/PanoplyJ/panoply.sh %f
Terminal=false
Type=Application
Categories=Science;Education;
EOF
chmod +x /home/ga/Desktop/Panoply.desktop
chown ga:ga /home/ga/Desktop/Panoply.desktop

# Create launch helper script
cat > /home/ga/Desktop/launch_panoply.sh << 'LAUNCHER'
#!/bin/bash
export DISPLAY=:1
/opt/PanoplyJ/panoply.sh "$@" &
LAUNCHER
chmod +x /home/ga/Desktop/launch_panoply.sh
chown ga:ga /home/ga/Desktop/launch_panoply.sh

# Do a warm-up launch to initialize Panoply preferences and dismiss first-run dialogs
echo "Performing warm-up launch of Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
echo "Waiting for Panoply window to appear..."
TIMEOUT=60
ELAPSED=0
PANOPLY_FOUND=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "panoply"; then
        PANOPLY_FOUND=true
        echo "Panoply window detected after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$PANOPLY_FOUND" = "false" ]; then
    echo "Warning: Panoply window not detected within ${TIMEOUT}s"
    echo "Checking if Java process is running..."
    ps aux | grep -i panoply || true
    ps aux | grep java || true
fi

# Let Panoply fully initialize
sleep 5

# Dismiss any first-run dialogs by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Close the warm-up instance
echo "Closing warm-up Panoply instance..."
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 3

# Set ownership
chown -R ga:ga "$DATA_DIR"
chown -R ga:ga "$CONFIG_DIR"
chown -R ga:ga /home/ga/Desktop
chown -R ga:ga /home/ga/Documents

echo "=== NASA Panoply setup complete ==="
echo "Data files: $DATA_DIR"
ls -lh "$DATA_DIR/"
