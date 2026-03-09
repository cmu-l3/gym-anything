#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enhance Dark Dashcam Result ==="

# Ensure VLC config is written by closing VLC gracefully
if is_vlc_running; then
    echo "Preparing to capture VLC configuration..."
    
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try to take a snapshot of enhanced video for visual verification
    echo "Attempting to capture enhanced frame snapshot..."
    su - ga -c "DISPLAY=:1 xdotool key shift+s" 2>/dev/null || true
    sleep 1
    
    # Close VLC to ensure config is saved
    echo "Closing VLC to save configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # If VLC still running, force close
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Copy VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "✅ Copying VLC configuration..."
    cp "$VLC_RC" /tmp/vlc_enhance_config.txt
    
    # Extract relevant settings for logging
    echo "Configuration settings:"
    grep -E "^(brightness|contrast|gamma|hue|saturation|video-filter|adjust-enabled)=" "$VLC_RC" || echo "  (no effects settings found)"
else
    echo "⚠️ VLC configuration file not found"
fi

# Check for snapshots (enhanced frame)
SNAPSHOT_DIR="/home/ga/Pictures/vlc"
LATEST_SNAPSHOT=$(ls -t "$SNAPSHOT_DIR"/vlc-snap* 2>/dev/null | head -1)

if [ -n "$LATEST_SNAPSHOT" ]; then
    echo "✅ Enhanced snapshot found: $LATEST_SNAPSHOT"
    cp "$LATEST_SNAPSHOT" /tmp/vlc_enhanced_frame.png
else
    echo "ℹ️ No snapshot captured (not required for verification)"
fi

# Copy reference dark frame if it exists
DARK_FRAME="/home/ga/Pictures/vlc/original_dark_frame.png"
if [ -f "$DARK_FRAME" ]; then
    cp "$DARK_FRAME" /tmp/vlc_dark_reference.png
    echo "✅ Reference dark frame copied"
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_enhance_completed.txt
echo "Brightness enhancement task completed" >> /tmp/vlc_enhance_completed.txt

echo "=== Export Complete ==="