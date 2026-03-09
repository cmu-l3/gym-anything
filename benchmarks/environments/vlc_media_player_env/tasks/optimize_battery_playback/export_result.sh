#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Optimize Battery Playback Result ==="

# Check if VLC config file exists
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config file found"
    
    # Copy config to /tmp for verification
    cp "$VLC_RC" /tmp/vlc_battery_config.vlcrc
    
    # Log some key settings for debugging
    echo "Current settings snapshot:"
    echo "=========================="
    grep -E "^(avcodec-hw|avcodec-skiploopfilter|video-filter|vout-filter|deinterlace)" "$VLC_RC" || echo "  (No relevant settings found in config)"
    echo "=========================="
    
    # Extract key settings for result summary
    HW_ACCEL=$(grep "^avcodec-hw=" "$VLC_RC" | cut -d= -f2 || echo "none")
    SKIP_FILTER=$(grep "^avcodec-skiploopfilter=" "$VLC_RC" | cut -d= -f2 || echo "0")
    VIDEO_FILTER=$(grep "^video-filter=" "$VLC_RC" | cut -d= -f2 || echo "")
    
    cat > /tmp/vlc_battery_summary.txt << EOF
Battery Optimization Summary
============================
Hardware Acceleration: $HW_ACCEL
Skip Loop Filter: $SKIP_FILTER
Video Filters: ${VIDEO_FILTER:-none}
Config File: Exported to /tmp/vlc_battery_config.vlcrc
Timestamp: $(date)
EOF
    
    echo "✅ Config exported to /tmp/vlc_battery_config.vlcrc"
    cat /tmp/vlc_battery_summary.txt
    
else
    echo "⚠️ VLC config file not found at: $VLC_RC"
    echo "This may indicate VLC was not configured or settings were not saved"
    
    # Create empty placeholder for verifier
    touch /tmp/vlc_battery_config.vlcrc
    echo "❌ Config file missing" > /tmp/vlc_battery_summary.txt
fi

# Close VLC gracefully if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try graceful close first
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga || true
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_battery_completed.txt
echo "Battery optimization task export completed" >> /tmp/vlc_battery_completed.txt

echo "=== Export Complete ==="