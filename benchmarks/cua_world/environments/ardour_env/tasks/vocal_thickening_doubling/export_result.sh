#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Vocal Thickening Doubling Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        # Activate window and send Ctrl+S to save
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Read baseline
INITIAL_TRACKS=$(cat /tmp/initial_track_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Current state
CURRENT_TRACKS="0"
SESSION_MODIFIED="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_TRACKS=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    SESSION_MODIFIED=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo "0")
fi

# Get track names
TRACK_NAMES=""
if [ -f "$SESSION_FILE" ]; then
    TRACK_NAMES=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$SESSION_FILE')
    root = tree.getroot()
    names = []
    for route in root.iter('Route'):
        flags = route.get('flags', '')
        if 'MasterOut' not in flags and 'MonitorOut' not in flags:
            if route.get('default-type') == 'audio':
                names.append(route.get('name', ''))
    print(','.join(names))
except:
    print('')
" 2>/dev/null || echo "")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/vocal_thickening_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "initial_track_count": $INITIAL_TRACKS,
    "current_track_count": $CURRENT_TRACKS,
    "track_names": "$TRACK_NAMES",
    "task_start_timestamp": $TASK_START,
    "session_modified_timestamp": $SESSION_MODIFIED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/vocal_thickening_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/vocal_thickening_result.json
chmod 666 /tmp/vocal_thickening_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/vocal_thickening_result.json"
echo "=== Export Complete ==="