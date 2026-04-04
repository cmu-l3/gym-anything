#!/bin/bash
set -e

echo "=== Setting up GCompris ==="

# Wait for desktop to be ready
sleep 5

# Determine the correct GCompris binary
# gcompris-qt installs to /usr/games/ on Ubuntu
if [ -x "/usr/games/gcompris-qt" ]; then
    GCOMPRIS_BIN="/usr/games/gcompris-qt"
elif command -v gcompris-qt &> /dev/null; then
    GCOMPRIS_BIN="gcompris-qt"
elif command -v gcompris &> /dev/null; then
    GCOMPRIS_BIN="gcompris"
else
    echo "ERROR: GCompris binary not found"
    exit 1
fi
echo "Using GCompris binary: $GCOMPRIS_BIN"

# Create GCompris config directory for the ga user
mkdir -p /home/ga/.config/gcompris-qt
chown -R ga:ga /home/ga/.config/gcompris-qt

# Write a config file to suppress first-run dialogs and configure fullscreen off
cat > /home/ga/.config/gcompris-qt/gcompris-qt.conf << 'EOF'
[General]
fullscreen=false
isFirstRun=false
enableAudio=false
showLockAtStart=false
filterLevelMin=1
filterLevelMax=6
EOF
chown ga:ga /home/ga/.config/gcompris-qt/gcompris-qt.conf

# Also handle legacy gcompris config
mkdir -p /home/ga/.config/gcompris
cat > /home/ga/.config/gcompris/gcompris.conf << 'EOF'
[General]
fullscreen=false
isFirstRun=false
enableAudio=false
EOF
chown -R ga:ga /home/ga/.config/gcompris

# Warm-up launch as ga user (post_start runs as root, so use sudo -u ga)
echo "Performing warm-up launch..."
sudo -u ga DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority "$GCOMPRIS_BIN" -m &
sleep 10

# Check if GCompris window appeared
if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "gcompris"; then
    echo "GCompris window detected, dismissing any dialogs..."
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
    sleep 1
else
    echo "WARNING: GCompris window not detected during warm-up"
fi

# Kill GCompris after warm-up
pkill -f "$GCOMPRIS_BIN" 2>/dev/null || true
sleep 2

echo "=== GCompris setup complete ==="
