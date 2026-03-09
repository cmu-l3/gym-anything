#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting DVD Navigation Result ==="

# Initialize result variables
DVD_MODE="false"
TITLE_NUMBER=""
ISO_LOADED="false"
PLAYBACK_TIME=0
RUNTIME_CAPTURED="false"

# Query VLC RC interface for DVD/title information
if is_vlc_running; then
    echo "Querying VLC RC interface..."
    
    # Get detailed status
    RC_STATUS=$(echo "status" | nc -w 3 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_STATUS" ]; then
        echo "RC status output:"
        echo "$RC_STATUS"
        
        # Check for DVD/disc mode indicators
        if echo "$RC_STATUS" | grep -qi "dvd\|disc\|title"; then
            DVD_MODE="true"
            RUNTIME_CAPTURED="true"
        fi
        
        # Try to extract title number
        # VLC may report "title X/Y" or "( title X )"
        TITLE_NUM=$(echo "$RC_STATUS" | grep -oP '(?:title[\s:]+)\K\d+' | head -1)
        if [ -n "$TITLE_NUM" ]; then
            TITLE_NUMBER="$TITLE_NUM"
            echo "✅ Title number detected: $TITLE_NUMBER"
        fi
        
        # Extract playback time (in seconds)
        TIME_SEC=$(echo "$RC_STATUS" | grep -oP '(?:time[\s:]+)\K\d+' | head -1)
        if [ -n "$TIME_SEC" ]; then
            PLAYBACK_TIME="$TIME_SEC"
            echo "Playback time: ${PLAYBACK_TIME}s"
        fi
    fi
    
    # Try alternative RC commands for title info
    if [ -z "$TITLE_NUMBER" ]; then
        TITLE_INFO=$(echo "get_title" | nc -w 2 localhost 9999 2>/dev/null || echo "")
        if [ -n "$TITLE_INFO" ]; then
            TITLE_NUMBER=$(echo "$TITLE_INFO" | grep -oP '\d+' | head -1)
        fi
    fi
    
    # Check current playing item for ISO reference
    INFO_OUTPUT=$(echo "info" | nc -w 3 localhost 9999 2>/dev/null || echo "")
    if echo "$INFO_OUTPUT" | grep -q "sample_movie.iso"; then
        ISO_LOADED="true"
        echo "✅ ISO file detected in playback"
    fi
fi

# Fallback: Check VLC window title
if [ "$DVD_MODE" = "false" ] || [ -z "$TITLE_NUMBER" ]; then
    echo "Checking window title for DVD information..."
    WINDOW_TITLE=$(wmctrl -l | grep -i "vlc" || true)
    
    if echo "$WINDOW_TITLE" | grep -qi "title.*2\|dvd"; then
        DVD_MODE="true"
        if echo "$WINDOW_TITLE" | grep -qi "title.*2"; then
            TITLE_NUMBER="2"
            echo "✅ Title 2 detected from window title"
        fi
    fi
    
    if echo "$WINDOW_TITLE" | grep -q "sample_movie.iso"; then
        ISO_LOADED="true"
    fi
fi

# Check VLC config for recent items
VLC_CONFIG="/home/ga/.config/vlc/vlc-qt-interface.conf"
if [ "$ISO_LOADED" = "false" ] && [ -f "$VLC_CONFIG" ]; then
    if grep -q "sample_movie.iso\|dvd://" "$VLC_CONFIG"; then
        ISO_LOADED="true"
        echo "ISO detected in VLC config"
    fi
fi

# Copy VLC log for verification
if [ -f /tmp/vlc_dvd_task.log ]; then
    cp /tmp/vlc_dvd_task.log /tmp/vlc_dvd_export.log
fi

# Close VLC
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
        kill_vlc ga
    fi
fi

# Write JSON result file
cat > /tmp/vlc_dvd_result.json <<EOF
{
    "iso_loaded": $ISO_LOADED,
    "dvd_mode": $DVD_MODE,
    "title_number": "$TITLE_NUMBER",
    "playback_time": $PLAYBACK_TIME,
    "runtime_captured": $RUNTIME_CAPTURED
}
EOF

echo "✅ DVD navigation result saved to /tmp/vlc_dvd_result.json"
cat /tmp/vlc_dvd_result.json

echo "$(date)" > /tmp/vlc_dvd_completed.txt
echo "DVD navigation task completed" >> /tmp/vlc_dvd_completed.txt

echo "=== Export Complete ==="