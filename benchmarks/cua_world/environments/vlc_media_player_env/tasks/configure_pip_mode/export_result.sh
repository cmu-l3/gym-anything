#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure PiP Mode Result ==="

# Initialize result data
WINDOW_DATA="{}"
WINDOW_FOUND="false"
AOT_PROPERTY="false"
VIDEO_PLAYING="false"
AOT_TEST_PASSED="false"

# Get VLC window information
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    
    if [ -n "$wid" ]; then
        WINDOW_FOUND="true"
        echo "VLC window ID: $wid"
        
        # Get window geometry using wmctrl
        GEOMETRY=$(su - ga -c "DISPLAY=:1 wmctrl -lG" | grep -i "VLC media player" | head -1)
        
        if [ -n "$GEOMETRY" ]; then
            # Parse geometry: WID DESKTOP X Y WIDTH HEIGHT CLIENT_MACHINE TITLE
            read -r win_id desktop x y width height rest <<< "$GEOMETRY"
            
            echo "Window geometry: X=$x Y=$y Width=$width Height=$height"
            
            # Get screen resolution
            SCREEN_WIDTH=$(su - ga -c "DISPLAY=:1 xdpyinfo | awk '/dimensions:/{print \$2}'" | cut -d'x' -f1)
            SCREEN_HEIGHT=$(su - ga -c "DISPLAY=:1 xdpyinfo | awk '/dimensions:/{print \$2}'" | cut -d'x' -f2)
            
            echo "Screen resolution: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"
            
            # Build window data JSON
            WINDOW_DATA=$(cat <<EOF
{
    "x": $x,
    "y": $y,
    "width": $width,
    "height": $height,
    "screen_width": $SCREEN_WIDTH,
    "screen_height": $SCREEN_HEIGHT
}
EOF
            )
        fi
        
        # Check X11 always-on-top property (_NET_WM_STATE_ABOVE)
        AOT_CHECK=$(su - ga -c "DISPLAY=:1 xprop -id $wid _NET_WM_STATE" 2>/dev/null || echo "")
        
        if echo "$AOT_CHECK" | grep -q "_NET_WM_STATE_ABOVE"; then
            AOT_PROPERTY="true"
            echo "✅ Always-on-top X11 property detected"
        else
            echo "⚠️ Always-on-top X11 property NOT detected"
        fi
        
        # Check if video is playing (not paused)
        # We can check this by looking at the window title or trying to detect playback state
        WINDOW_TITLE=$(su - ga -c "DISPLAY=:1 xdotool getwindowname $wid" 2>/dev/null || echo "")
        
        # VLC shows media name in title when playing; if paused, often shows "VLC media player"
        if [ -n "$WINDOW_TITLE" ] && [ "$WINDOW_TITLE" != "VLC media player" ]; then
            VIDEO_PLAYING="true"
            echo "Video appears to be playing (title: $WINDOW_TITLE)"
        else
            echo "Video may be paused or stopped"
        fi
    else
        echo "⚠️ Could not find VLC window ID"
    fi
    
    # Test always-on-top behavior by launching a test window
    echo "Testing always-on-top behavior..."
    TEST_WINDOW_PID=""
    
    # Launch a test xterm window
    su - ga -c "DISPLAY=:1 xterm -e 'echo Always-on-top test window; sleep 5' > /tmp/test_window.log 2>&1 &"
    TEST_WINDOW_PID=$!
    
    sleep 2
    
    # Get test window ID
    TEST_WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'Always-on-top test' 2>/dev/null | head -1" || echo "")
    
    if [ -z "$TEST_WID" ]; then
        # Try alternative method
        TEST_WID=$(su - ga -c "DISPLAY=:1 xdotool search --class xterm 2>/dev/null | tail -1" || echo "")
    fi
    
    if [ -n "$TEST_WID" ]; then
        # Focus the test window
        su - ga -c "DISPLAY=:1 xdotool windowactivate $TEST_WID" 2>/dev/null || true
        sleep 1
        
        # Check if VLC window is still on top by checking window stacking
        STACKING=$(su - ga -c "DISPLAY=:1 xprop -root _NET_CLIENT_LIST_STACKING" 2>/dev/null | grep -oP '0x[0-9a-f]+' || echo "")
        
        # Convert window IDs to decimal for comparison
        VLC_WID_DEC=$((wid))
        TEST_WID_DEC=$((TEST_WID))
        
        # Check if VLC appears later in stacking list (meaning it's on top)
        # This is a simplified check - in reality, _NET_WM_STATE_ABOVE is more reliable
        if [ "$AOT_PROPERTY" = "true" ]; then
            AOT_TEST_PASSED="true"
            echo "✅ Always-on-top test passed (property verified)"
        else
            echo "⚠️ Always-on-top test inconclusive"
        fi
        
        # Clean up test window
        su - ga -c "DISPLAY=:1 xdotool windowkill $TEST_WID" 2>/dev/null || true
    else
        echo "⚠️ Could not launch test window for always-on-top verification"
        # If we have the property, still consider it passed
        if [ "$AOT_PROPERTY" = "true" ]; then
            AOT_TEST_PASSED="true"
        fi
    fi
else
    echo "⚠️ VLC is not running"
fi

# Read VLC config to check video-on-top setting
VLC_RC="/home/ga/.config/vlc/vlcrc"
CONFIG_AOT="false"
CONFIG_AOT_VALUE=""

if is_vlc_running; then
    # Close VLC gracefully to save preferences
    echo "Closing VLC to save preferences..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Now read the config file
if [ -f "$VLC_RC" ]; then
    if grep -q "^video-on-top=1" "$VLC_RC"; then
        CONFIG_AOT="true"
        CONFIG_AOT_VALUE="1"
        echo "✅ video-on-top=1 found in vlcrc"
    elif grep -q "^video-on-top=" "$VLC_RC"; then
        CONFIG_AOT_VALUE=$(grep "^video-on-top=" "$VLC_RC" | cut -d= -f2)
        echo "⚠️ video-on-top=$CONFIG_AOT_VALUE (not enabled)"
    else
        echo "⚠️ video-on-top setting not found in vlcrc"
    fi
fi

# Write comprehensive JSON result file
cat > /tmp/vlc_pip_result.json <<EOF
{
    "window_found": $WINDOW_FOUND,
    "window_data": $WINDOW_DATA,
    "always_on_top_property": $AOT_PROPERTY,
    "always_on_top_config": $CONFIG_AOT,
    "config_aot_value": "$CONFIG_AOT_VALUE",
    "video_playing": $VIDEO_PLAYING,
    "always_on_top_test_passed": $AOT_TEST_PASSED
}
EOF

echo "✅ PiP mode result saved to /tmp/vlc_pip_result.json"
cat /tmp/vlc_pip_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_pip_completed.txt
echo "Configure PiP mode task completed" >> /tmp/vlc_pip_completed.txt

echo "=== Export Complete ==="