#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Podcast Production Mix Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
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
INITIAL_MARKERS=$(cat /tmp/initial_marker_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Current state
CURRENT_TRACKS="0"
CURRENT_MARKERS="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_TRACKS=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
    CURRENT_MARKERS=$(grep -c '<Location.*IsMark' "$SESSION_FILE" 2>/dev/null || echo "0")
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

# Count exported podcast files
EXPORT_COUNT=0
EXPORT_DIR="/home/ga/Audio/podcast_final"
if [ -d "$EXPORT_DIR" ]; then
    EXPORT_COUNT=$(find "$EXPORT_DIR" -name "*.wav" -type f 2>/dev/null | wc -l)
fi

# Create result JSON
cat > /tmp/podcast_production_mix_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "initial_track_count": $INITIAL_TRACKS,
    "current_track_count": $CURRENT_TRACKS,
    "initial_marker_count": $INITIAL_MARKERS,
    "current_marker_count": $CURRENT_MARKERS,
    "track_names": "$TRACK_NAMES",
    "export_count": $EXPORT_COUNT,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/podcast_production_mix_result.json"
echo "=== Export Complete ==="
