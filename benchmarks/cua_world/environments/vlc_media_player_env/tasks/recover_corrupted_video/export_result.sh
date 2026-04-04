#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Recover Corrupted Video Result ==="

# Copy VLC config to check settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Copying VLC config..."
    cp "$VLC_RC" /tmp/vlc_recovery_config.txt
    echo "✅ VLC config copied"
    
    # Show relevant settings for debugging
    echo "Current error-handling settings:"
    grep -E "avi-index|file-caching|avcodec-skip|avcodec-fast|avcodec-hw" "$VLC_RC" || echo "No settings found"
else
    echo "⚠️ VLC config not found"
    touch /tmp/vlc_recovery_config.txt
fi

# Copy VLC logs
if [ -f /tmp/vlc_recovery_task.log ]; then
    cp /tmp/vlc_recovery_task.log /tmp/vlc_recovery_playback.log
    echo "✅ VLC log copied"
else
    echo "⚠️ VLC log not found"
    touch /tmp/vlc_recovery_playback.log
fi

# Get VLC messages/debug log if available
VLC_LOG_DIR="/home/ga/.local/share/vlc"
if [ -d "$VLC_LOG_DIR" ]; then
    LATEST_LOG=$(find "$VLC_LOG_DIR" -name "*.log" -type f -mmin -10 2>/dev/null | head -1 || echo "")
    if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
        echo "Found VLC debug log: $LATEST_LOG"
        cat "$LATEST_LOG" >> /tmp/vlc_recovery_playback.log 2>/dev/null || true
    fi
fi

# Check if VLC is still running and capture runtime info
if is_vlc_running; then
    echo "VLC still running, capturing runtime info..."
    
    # Get process info
    ps aux | grep "[v]lc" > /tmp/vlc_recovery_info.txt 2>&1 || true
    
    # Try to capture any error messages from VLC window title or logs
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        xdotool getwindowname "$wid" >> /tmp/vlc_recovery_info.txt 2>&1 || true
    fi
fi

# Close VLC
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
        kill_vlc ga || true
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_recovery_completed.txt
echo "Corrupted video recovery task completed" >> /tmp/vlc_recovery_completed.txt

echo "=== Export Complete ==="