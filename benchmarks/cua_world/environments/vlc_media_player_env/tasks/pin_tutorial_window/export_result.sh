#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Pin Tutorial Window Result ==="

# Initialize variables
WINDOW_X=0
WINDOW_Y=0
WINDOW_WIDTH=0
WINDOW_HEIGHT=0
SCREEN_WIDTH=1920
SCREEN_HEIGHT=1080
ALWAYS_ON_TOP="false"
WINDOW_STATE=""
WINDOW_ID=""

# Get screen resolution
if command -v xdotool &> /dev/null; then
    SCREEN_GEOM=$(su - ga -c "DISPLAY=:1 xdotool getdisplaygeometry" 2>/dev/null || echo "1920 1080")
    SCREEN_WIDTH=$(echo "$SCREEN_GEOM" | awk '{print $1}')
    SCREEN_HEIGHT=$(echo "$SCREEN_GEOM" | awk '{print $2}')
    echo "Screen resolution: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"
fi

# Get VLC window info
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    
    if [ -n "$wid" ]; then
        WINDOW_ID="$wid"
        echo "VLC window ID: $wid"
        
        # Get window geometry using xdotool
        WINDOW_GEOM=$(su - ga -c "DISPLAY=:1 xdotool getwindowgeometry $wid" 2>/dev/null || echo "")
        
        if [ -n "$WINDOW_GEOM" ]; then
            # Parse geometry - format is:
            # Window 12345678
            #   Position: 100,50 (screen: 0)
            #   Geometry: 800x600
            
            WINDOW_X=$(echo "$WINDOW_GEOM" | grep "Position:" | sed 's/.*Position: \([0-9]*\),.*/\1/' || echo "0")
            WINDOW_Y=$(echo "$WINDOW_GEOM" | grep "Position:" | sed 's/.*Position: [0-9]*,\([0-9]*\).*/\1/' || echo "0")
            WINDOW_WIDTH=$(echo "$WINDOW_GEOM" | grep "Geometry:" | sed 's/.*Geometry: \([0-9]*\)x.*/\1/' || echo "0")
            WINDOW_HEIGHT=$(echo "$WINDOW_GEOM" | grep "Geometry:" | sed 's/.*Geometry: [0-9]*x\([0-9]*\)/\1/' || echo "0")
            
            echo "Window geometry: ${WINDOW_WIDTH}x${WINDOW_HEIGHT} at (${WINDOW_X},${WINDOW_Y})"
        else
            echo "⚠️ Could not get window geometry"
        fi
        
        # Get window state (check for always-on-top)
        WINDOW_STATE=$(su - ga -c "DISPLAY=:1 xprop -id $wid _NET_WM_STATE" 2>/dev/null || echo "")
        
        if [ -n "$WINDOW_STATE" ]; then
            echo "Window state: $WINDOW_STATE"
            
            # Check if _NET_WM_STATE_ABOVE is present (indicates always-on-top)
            if echo "$WINDOW_STATE" | grep -q "_NET_WM_STATE_ABOVE"; then
                ALWAYS_ON_TOP="true"
                echo "✅ Always-on-top is ENABLED"
            else
                echo "⚠️ Always-on-top is NOT enabled"
            fi
        else
            echo "⚠️ Could not get window state"
        fi
        
    else
        echo "⚠️ Could not get VLC window ID"
    fi
else
    echo "⚠️ VLC is not running"
fi

# Create JSON result file
cat > /tmp/vlc_window_config.json <<EOF
{
    "window_id": "$WINDOW_ID",
    "x": $WINDOW_X,
    "y": $WINDOW_Y,
    "width": $WINDOW_WIDTH,
    "height": $WINDOW_HEIGHT,
    "screen_width": $SCREEN_WIDTH,
    "screen_height": $SCREEN_HEIGHT,
    "always_on_top": $ALWAYS_ON_TOP,
    "window_state": "$(echo "$WINDOW_STATE" | tr '\n' ' ' | sed 's/"/\\"/g')"
}
EOF

echo "✅ Window configuration saved to /tmp/vlc_window_config.json"
cat /tmp/vlc_window_config.json

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_tutorial_window_completed.txt
echo "Tutorial window task completed" >> /tmp/vlc_tutorial_window_completed.txt

echo "=== Export Complete ==="