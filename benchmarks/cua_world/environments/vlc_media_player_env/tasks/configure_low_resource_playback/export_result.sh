#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Low Resource Playback Result ==="

# Before closing VLC, give time for any settings changes to be written
echo "Waiting for settings to be written..."
sleep 2

# Close VLC gracefully to ensure config is saved
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Copy VLC config file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config file found"
    cp "$VLC_RC" /tmp/vlc_lowres_config.txt
    
    # Extract and log relevant settings for debugging
    echo "=== Performance Settings Found ==="
    grep -E "^(avcodec-hw|skip-frames|skip-late|vout|file-caching|video-filter|deinterlace)=" "$VLC_RC" || echo "No performance settings found"
    echo "================================"
else
    echo "⚠️ VLC config file not found"
    touch /tmp/vlc_lowres_config.txt
fi

# Parse config and create JSON result for easier verification
SETTINGS_JSON="{"

# Check for hardware acceleration
HW_ACCEL=$(grep "^avcodec-hw=" "$VLC_RC" 2>/dev/null | cut -d= -f2 || echo "none")
SETTINGS_JSON="${SETTINGS_JSON}\"hw_accel\": \"${HW_ACCEL}\""

# Check for frame skipping
SKIP_FRAMES=$(grep "^skip-frames=" "$VLC_RC" 2>/dev/null | cut -d= -f2 || echo "0")
SETTINGS_JSON="${SETTINGS_JSON}, \"skip_frames\": \"${SKIP_FRAMES}\""

# Check for video output
VOUT=$(grep "^vout=" "$VLC_RC" 2>/dev/null | cut -d= -f2 || echo "default")
SETTINGS_JSON="${SETTINGS_JSON}, \"vout\": \"${VOUT}\""

# Check for file caching
FILE_CACHE=$(grep "^file-caching=" "$VLC_RC" 2>/dev/null | cut -d= -f2 || echo "1000")
SETTINGS_JSON="${SETTINGS_JSON}, \"file_caching\": \"${FILE_CACHE}\""

# Check for video filters
VIDEO_FILTER=$(grep "^video-filter=" "$VLC_RC" 2>/dev/null | cut -d= -f2 || echo "")
SETTINGS_JSON="${SETTINGS_JSON}, \"video_filter\": \"${VIDEO_FILTER}\""

# Check for deinterlacing
DEINTERLACE=$(grep "^deinterlace=" "$VLC_RC" 2>/dev/null | cut -d= -f2 || echo "0")
SETTINGS_JSON="${SETTINGS_JSON}, \"deinterlace\": \"${DEINTERLACE}\""

SETTINGS_JSON="${SETTINGS_JSON}}"

# Write JSON result
echo "$SETTINGS_JSON" > /tmp/vlc_lowres_result.json

echo "✅ Settings result saved to /tmp/vlc_lowres_result.json"
cat /tmp/vlc_lowres_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_lowres_completed.txt
echo "Low resource playback configuration task completed" >> /tmp/vlc_lowres_completed.txt

echo "=== Export Complete ==="