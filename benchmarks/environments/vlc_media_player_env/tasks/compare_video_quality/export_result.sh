#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Video Quality Result ==="

# Check for screenshots in comparison directory
COMPARISON_DIR="/home/ga/Pictures/comparison"

SCREENSHOT_A="$COMPARISON_DIR/version_a_frame.png"
SCREENSHOT_B="$COMPARISON_DIR/version_b_frame.png"

# Check if properly named screenshots exist
if [ -f "$SCREENSHOT_A" ] && [ -f "$SCREENSHOT_B" ]; then
    echo "✅ Both screenshots found with correct names"
    cp "$SCREENSHOT_A" /tmp/vlc_compare_screenshot_a.png
    cp "$SCREENSHOT_B" /tmp/vlc_compare_screenshot_b.png
else
    echo "⚠️ Screenshots not found with expected names"
    
    # Look for any VLC snapshots in comparison directory
    SNAPSHOTS=($(ls -t "$COMPARISON_DIR"/vlc-snap*.png 2>/dev/null || echo ""))
    SNAP_COUNT=${#SNAPSHOTS[@]}
    
    if [ $SNAP_COUNT -ge 2 ]; then
        echo "Found $SNAP_COUNT VLC snapshots, using two most recent"
        cp "${SNAPSHOTS[0]}" /tmp/vlc_compare_screenshot_a.png || true
        cp "${SNAPSHOTS[1]}" /tmp/vlc_compare_screenshot_b.png || true
    elif [ $SNAP_COUNT -eq 1 ]; then
        echo "Found only 1 snapshot"
        cp "${SNAPSHOTS[0]}" /tmp/vlc_compare_screenshot_a.png || true
    else
        echo "No snapshots found in comparison directory"
        
        # Check default VLC snapshot directory as fallback
        VLC_SNAP_DIR="/home/ga/Pictures/vlc"
        if [ -d "$VLC_SNAP_DIR" ]; then
            RECENT_SNAPS=($(find "$VLC_SNAP_DIR" -name "vlc-snap*.png" -mmin -10 2>/dev/null | sort -r || echo ""))
            RECENT_COUNT=${#RECENT_SNAPS[@]}
            
            if [ $RECENT_COUNT -ge 2 ]; then
                echo "Found $RECENT_COUNT recent snapshots in default directory"
                cp "${RECENT_SNAPS[0]}" /tmp/vlc_compare_screenshot_a.png || true
                cp "${RECENT_SNAPS[1]}" /tmp/vlc_compare_screenshot_b.png || true
            elif [ $RECENT_COUNT -eq 1 ]; then
                echo "Found 1 recent snapshot in default directory"
                cp "${RECENT_SNAPS[0]}" /tmp/vlc_compare_screenshot_a.png || true
            fi
        fi
    fi
fi

# List what we captured
echo "Captured files:"
ls -lh /tmp/vlc_compare_screenshot*.png 2>/dev/null || echo "No screenshots captured"

# Close all VLC instances
echo "Closing VLC instances..."
if is_vlc_running; then
    # Try to close gracefully
    WINDOW_IDS=$(wmctrl -l | grep -i vlc | awk '{print $1}' || echo "")
    
    for wid in $WINDOW_IDS; do
        echo "Closing window $wid"
        wmctrl -i -c "$wid" 2>/dev/null || true
        sleep 0.5
    done
    
    # Wait a moment
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing remaining VLC processes"
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_compare_completed.txt
echo "Compare video quality task completed" >> /tmp/vlc_compare_completed.txt

# Write summary JSON
cat > /tmp/vlc_compare_result.json <<EOF
{
    "task": "compare_video_quality",
    "timestamp": "$(date -Iseconds)",
    "screenshot_a_exists": $([ -f /tmp/vlc_compare_screenshot_a.png ] && echo "true" || echo "false"),
    "screenshot_b_exists": $([ -f /tmp/vlc_compare_screenshot_b.png ] && echo "true" || echo "false")
}
EOF

cat /tmp/vlc_compare_result.json

echo "=== Export Complete ==="