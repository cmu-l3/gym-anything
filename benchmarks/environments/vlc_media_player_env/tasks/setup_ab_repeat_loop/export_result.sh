#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting A-B Repeat Loop Task Results ==="

# Initialize result variables
AB_LOOP_ACTIVE="false"
LOOP_START=""
LOOP_END=""
VIDEO_LOADED="false"
VLC_STATUS=""
RUNTIME_CAPTURED="false"

# Check if VLC is running
if is_vlc_running; then
    echo "✅ VLC is running"
    VLC_RUNNING="true"
    
    # Try to query VLC RC interface for loop status and playback position
    echo "Querying VLC RC interface..."
    
    # Get current status which includes playback info
    RC_STATUS=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_STATUS" ]; then
        VLC_STATUS="$RC_STATUS"
        echo "RC status received (length: ${#RC_STATUS} chars)"
        
        # Check if research_interview is playing
        if echo "$RC_STATUS" | grep -qi "research_interview"; then
            VIDEO_LOADED="true"
            echo "✅ Interview video is loaded"
        fi
        
        # VLC RC interface doesn't directly expose A-B loop state easily
        # But we can check for repeat/loop status
        
        # Try to get current time to see if video is playing/looping
        CURRENT_TIME=$(echo "get_time" | nc -w 2 localhost 9999 2>/dev/null | grep -oP '\d+' | head -1 || echo "")
        
        if [ -n "$CURRENT_TIME" ]; then
            echo "Current playback time: ${CURRENT_TIME}s"
        fi
        
        # Try to detect loop state from is_playing and repeat settings
        IS_PLAYING=$(echo "is_playing" | nc -w 2 localhost 9999 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
        
        # Check for any loop-related output in status
        if echo "$RC_STATUS" | grep -qi "loop\|repeat"; then
            AB_LOOP_ACTIVE="true"
            echo "✅ Loop indicator found in RC status"
        fi
        
        RUNTIME_CAPTURED="true"
    else
        echo "⚠️ Could not query RC interface"
    fi
    
    # Alternative: Check VLC window title for indicators
    VLC_WINDOW_INFO=$(wmctrl -l | grep -i "vlc" || echo "")
    if echo "$VLC_WINDOW_INFO" | grep -qi "research_interview"; then
        VIDEO_LOADED="true"
    fi
    
else
    echo "⚠️ VLC is not running"
    VLC_RUNNING="false"
fi

# Take a screenshot of VLC to help with verification
echo "Taking screenshot for verification..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/vlc_ab_loop_screenshot.png" 2>&1 || true
    if [ -f /tmp/vlc_ab_loop_screenshot.png ]; then
        echo "✅ Screenshot captured"
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try RC interface first
    echo "quit" | nc -w 1 localhost 9999 2>/dev/null || true
    sleep 1
    
    # Fallback to keyboard
    if is_vlc_running; then
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    fi
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Fallback: Read VLC config file for any saved loop state
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_STATE_DIR="/home/ga/.local/share/vlc"

if [ -f "$VLC_RC" ]; then
    echo "Checking VLC config for loop settings..."
    
    # Check for any loop-related config
    if grep -qi "loop\|repeat" "$VLC_RC"; then
        AB_LOOP_CONFIG=$(grep -i "loop\|repeat" "$VLC_RC" || echo "")
        echo "Loop config found: $AB_LOOP_CONFIG"
    fi
fi

# Write comprehensive JSON result file
cat > /tmp/vlc_ab_loop_result.json <<EOF
{
    "vlc_running": $VLC_RUNNING,
    "video_loaded": $VIDEO_LOADED,
    "ab_loop_active": $AB_LOOP_ACTIVE,
    "loop_start_seconds": "${LOOP_START:-null}",
    "loop_end_seconds": "${LOOP_END:-null}",
    "runtime_captured": $RUNTIME_CAPTURED,
    "vlc_status_length": ${#VLC_STATUS},
    "screenshot_available": $([ -f /tmp/vlc_ab_loop_screenshot.png ] && echo "true" || echo "false")
}
EOF

echo ""
echo "✅ A-B loop result saved to /tmp/vlc_ab_loop_result.json"
cat /tmp/vlc_ab_loop_result.json
echo ""

# Create completion marker
echo "$(date)" > /tmp/vlc_ab_loop_completed.txt
echo "A-B repeat loop task export completed" >> /tmp/vlc_ab_loop_completed.txt
echo "VLC running: $VLC_RUNNING" >> /tmp/vlc_ab_loop_completed.txt
echo "Video loaded: $VIDEO_LOADED" >> /tmp/vlc_ab_loop_completed.txt

echo "=== Export Complete ==="