#!/bin/bash
set -e
echo "=== Setting up GLCM Texture Phase Discrimination task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Fiji_Data/raw/alloy
mkdir -p /home/ga/Fiji_Data/results/texture
chown -R ga:ga /home/ga/Fiji_Data

# Clean any previous results
rm -rf /home/ga/Fiji_Data/results/texture/*

# Download the eutectic alloy microstructure image
# Source: ImageJ sample images
ALLOY_IMG="/home/ga/Fiji_Data/raw/alloy/AuPbSn40.jpg"
IMAGE_URL="https://imagej.nih.gov/ij/images/AuPbSn40.jpg"
FALLBACK_URL="https://imagej.net/images/AuPbSn40.jpg"

if [ ! -f "$ALLOY_IMG" ]; then
    echo "Downloading AuPbSn40.jpg..."
    if ! wget -q --timeout=30 "$IMAGE_URL" -O "$ALLOY_IMG"; then
        echo "Primary download failed, trying fallback..."
        if ! wget -q --timeout=30 "$FALLBACK_URL" -O "$ALLOY_IMG"; then
            echo "ERROR: Could not download sample image."
            exit 1
        fi
    fi
fi

# Set permissions
chown ga:ga "$ALLOY_IMG"
chmod 644 "$ALLOY_IMG"

# Ensure Fiji is running
if ! pgrep -f "fiji\|ImageJ" > /dev/null 2>&1; then
    echo "Starting Fiji..."
    export DISPLAY=:1
    # Use the launch script if available, otherwise direct binary
    if [ -f "/home/ga/launch_fiji.sh" ]; then
        su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    else
        su - ga -c "DISPLAY=:1 /usr/local/bin/fiji" &
    fi
    sleep 8
fi

# Wait for Fiji window to appear
echo "Waiting for Fiji window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "fiji|imagej"; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize and focus Fiji
sleep 2
# Try to find the specific window ID to avoid ambiguity
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "fiji|imagej" | head -n 1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any startup dialogs (Esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Image location: $ALLOY_IMG"