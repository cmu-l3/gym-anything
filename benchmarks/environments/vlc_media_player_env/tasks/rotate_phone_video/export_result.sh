#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Rotate Phone Video Result ==="

# Define paths
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="/home/ga/.config/vlc/vlcrc"
RESULT_DIR="/tmp/vlc_rotate_result"

# Create result directory
mkdir -p "$RESULT_DIR"

# Copy VLC configuration files for verification
echo "Copying VLC configuration files..."
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "$RESULT_DIR/vlcrc"
    echo "✅ VLC config copied"
    
    # Log relevant settings
    echo "Transform-related settings in vlcrc:"
    grep -E "(video-filter|vout-filter|transform)" "$VLC_RC" || echo "  (no transform settings found)"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Copy Qt interface config if it exists (alternative location for some settings)
if [ -f "$VLC_CONFIG_DIR/vlc-qt-interface.conf" ]; then
    cp "$VLC_CONFIG_DIR/vlc-qt-interface.conf" "$RESULT_DIR/"
    echo "Qt interface config copied"
fi

# Capture VLC process info if running
if is_vlc_running; then
    ps aux | grep vlc | grep -v grep > "$RESULT_DIR/vlc_process.txt" 2>&1 || true
    echo "VLC process info captured"
fi

# Take a screenshot to visually verify rotation (optional, for debugging)
if is_vlc_running; then
    echo "Capturing screenshot for visual verification..."
    su - ga -c "DISPLAY=:1 import -window root '$RESULT_DIR/vlc_screenshot.png' 2>/dev/null" || true
fi

# Copy result directory to standard location
cp -r "$RESULT_DIR"/* /tmp/ 2>/dev/null || true

# Create task metadata
cat > /tmp/vlc_rotate_task_info.json <<EOF
{
  "task_id": "rotate_phone_video@1",
  "timestamp": "$(date -Iseconds)",
  "video_file": "/home/ga/Videos/sideways_concert.mp4",
  "config_exported": true,
  "config_path": "$VLC_RC"
}
EOF

echo "✅ Task info saved"

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_rotate_completed.txt
echo "Rotate phone video task completed" >> /tmp/vlc_rotate_completed.txt

echo "=== Export Complete ==="
echo "Results exported to /tmp/"