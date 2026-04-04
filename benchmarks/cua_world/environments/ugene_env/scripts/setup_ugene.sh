#!/bin/bash
set -e

echo "=== Setting up UGENE for user ga ==="

# Wait for desktop to be ready
sleep 5

# Create user directories
mkdir -p /home/ga/UGENE_Data
mkdir -p /home/ga/.config/UGENE
mkdir -p /home/ga/Desktop

# Copy real bioinformatics data to user's workspace
if [ -d /opt/ugene_data ]; then
    cp -r /opt/ugene_data/* /home/ga/UGENE_Data/ 2>/dev/null || true
fi

# Also copy UGENE's built-in sample data if available
if [ -d /opt/ugene/data/samples ]; then
    mkdir -p /home/ga/UGENE_Data/samples
    cp -r /opt/ugene/data/samples/* /home/ga/UGENE_Data/samples/ 2>/dev/null || true
fi

# Create UGENE configuration to suppress first-run dialogs and tips
# UGENE stores settings in ~/.config/UGENE/ or ~/.config/Unipro/
mkdir -p /home/ga/.config/UGENE
mkdir -p /home/ga/.config/Unipro

# Create UGENE settings to disable update checks and first-run wizard
cat > /home/ga/.config/UGENE/UGENE.ini << 'EOF'
[General]
show_tips_on_startup=false
check_updates_on_startup=false
first_start=false
show_welcome=false

[updater]
check_updates=false

[main_window]
geometry=@ByteArray()
state=@ByteArray()
maximized=true
EOF

# Also create settings in alternate location
cp /home/ga/.config/UGENE/UGENE.ini /home/ga/.config/Unipro/UGENE.ini 2>/dev/null || true

# Create desktop launcher
cat > /home/ga/Desktop/ugene.desktop << 'EOF'
[Desktop Entry]
Name=UGENE
Comment=Bioinformatics Suite
Exec=/usr/local/bin/ugene
Icon=/opt/ugene/ugene.png
Terminal=false
Type=Application
Categories=Science;Biology;
EOF
chmod +x /home/ga/Desktop/ugene.desktop

# Create user launch script
cat > /home/ga/launch_ugene.sh << 'LAUNCH'
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
export LD_LIBRARY_PATH="/opt/ugene:$LD_LIBRARY_PATH"

# Allow X connections
xhost +local: 2>/dev/null || true

cd /opt/ugene
if [ -x ./ugeneui ]; then
    setsid ./ugeneui "$@" > /tmp/ugene.log 2>&1 &
elif [ -x ./ugene ]; then
    setsid ./ugene "$@" > /tmp/ugene.log 2>&1 &
else
    UGENE_BIN=$(find /opt/ugene -name "ugene*" -type f -executable | head -1)
    if [ -n "$UGENE_BIN" ]; then
        setsid "$UGENE_BIN" "$@" > /tmp/ugene.log 2>&1 &
    fi
fi
LAUNCH
chmod +x /home/ga/launch_ugene.sh

# Set ownership
chown -R ga:ga /home/ga/UGENE_Data
chown -R ga:ga /home/ga/.config/UGENE
chown -R ga:ga /home/ga/.config/Unipro
chown ga:ga /home/ga/Desktop/ugene.desktop
chown ga:ga /home/ga/launch_ugene.sh

# Warm-up launch to clear any first-run state
echo "Performing warm-up launch of UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xhost +local: 2>/dev/null || true"
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window to appear
WARMUP_TIMEOUT=60
WARMUP_ELAPSED=0
UGENE_STARTED=false
while [ $WARMUP_ELAPSED -lt $WARMUP_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${WARMUP_ELAPSED}s"
        UGENE_STARTED=true
        break
    fi
    sleep 2
    WARMUP_ELAPSED=$((WARMUP_ELAPSED + 2))
done

if [ "$UGENE_STARTED" = true ]; then
    # Give UI time to fully initialize and dismiss any startup dialogs
    sleep 5

    # Press Escape to dismiss any startup dialog/tip of the day
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    echo "Closing warm-up UGENE instance..."
    # Close UGENE cleanly
    pkill -f "ugene" 2>/dev/null || true
    sleep 3
    # Force kill if still running
    pkill -9 -f "ugene" 2>/dev/null || true
    sleep 2
else
    echo "WARNING: UGENE window did not appear during warm-up"
    pkill -f "ugene" 2>/dev/null || true
    sleep 2
fi

echo "=== UGENE setup complete ==="
echo "Data files:"
ls -la /home/ga/UGENE_Data/
