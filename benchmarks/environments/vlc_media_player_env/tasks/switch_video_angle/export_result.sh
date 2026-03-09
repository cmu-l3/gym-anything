#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Switch Video Angle Result ==="

# Create export directory
EXPORT_DIR="/tmp/task_export"
mkdir -p "$EXPORT_DIR"

# Capture VLC process information (check for explicit track selection)
echo "Capturing VLC process info..."
pgrep -fa vlc > "$EXPORT_DIR/vlc_processes.txt" 2>&1 || echo "No VLC process found" > "$EXPORT_DIR/vlc_processes.txt"

# Copy VLC logs if they exist
if [ -f /home/ga/.local/share/vlc/vlc-log.txt ]; then
    cp /home/ga/.local/share/vlc/vlc-log.txt "$EXPORT_DIR/vlc-log.txt" 2>/dev/null || true
fi

if [ -f /tmp/vlc_video_track_task.log ]; then
    cp /tmp/vlc_video_track_task.log "$EXPORT_DIR/vlc_messages.log" 2>/dev/null || true
fi

# Capture screenshot of current VLC window for visual verification
echo "Capturing screenshot..."
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        # Take screenshot of VLC window
        su - ga -c "DISPLAY=:1 import -window root '$EXPORT_DIR/final_screenshot.png'" 2>/dev/null || true
        
        # Also try to capture just the VLC window
        su - ga -c "DISPLAY=:1 import -window $wid '$EXPORT_DIR/vlc_window.png'" 2>/dev/null || true
    fi
fi

# Try to query VLC via DBus/MPRIS for current track info
echo "Querying VLC state via DBus..."
su - ga -c "DISPLAY=:1 dbus-send --print-reply --session \
    --dest=org.mpris.MediaPlayer2.vlc \
    /org/mpris/MediaPlayer2 \
    org.freedesktop.DBus.Properties.GetAll \
    string:org.mpris.MediaPlayer2.Player" \
    > "$EXPORT_DIR/vlc_dbus_state.txt" 2>&1 || echo "DBus query failed" > "$EXPORT_DIR/vlc_dbus_state.txt"

# Check VLC configuration for video track settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Checking VLC config for video track settings..."
    grep -E "video-track|vout" "$VLC_RC" > "$EXPORT_DIR/vlc_config_tracks.txt" 2>/dev/null || echo "No video track config found" > "$EXPORT_DIR/vlc_config_tracks.txt"
fi

# Analyze current video track from VLC's internal state
# We'll check the VLC log for track selection messages
if [ -f "$EXPORT_DIR/vlc_messages.log" ]; then
    echo "Analyzing VLC logs for track switching..."
    grep -i -E "track|video|stream|select" "$EXPORT_DIR/vlc_messages.log" > "$EXPORT_DIR/track_analysis.txt" 2>/dev/null || true
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_video_track_completed.txt
echo "Video track switch task completed" >> /tmp/vlc_video_track_completed.txt

# List all exported files
echo "✅ Exported files:"
ls -lh "$EXPORT_DIR/" 2>/dev/null || true

echo "=== Export Complete ==="