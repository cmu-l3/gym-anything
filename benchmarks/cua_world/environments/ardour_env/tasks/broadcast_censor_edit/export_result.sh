#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Broadcast Censor Edit Result ==="

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
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Current state
CURRENT_TRACKS="0"
if [ -f "$SESSION_FILE" ]; then
    CURRENT_TRACKS=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
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

# Check exported mix
EXPORT_FILE_EXISTS="false"
EXPORT_FILE_SIZE="0"
EXPORT_FILE_PATH="/home/ga/Audio/export/fcc_compliant_mix.wav"

if [ -f "$EXPORT_FILE_PATH" ]; then
    EXPORT_FILE_EXISTS="true"
    EXPORT_FILE_SIZE=$(stat -c %s "$EXPORT_FILE_PATH" 2>/dev/null || echo "0")
else
    # Fallback to searching the export directory for any WAV created recently
    ALT_FILE=$(find "/home/ga/Audio/export" -name "*.wav" -type f -cmin -30 | head -1)
    if [ -n "$ALT_FILE" ]; then
        EXPORT_FILE_EXISTS="true"
        EXPORT_FILE_PATH="$ALT_FILE"
        EXPORT_FILE_SIZE=$(stat -c %s "$ALT_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create result JSON
cat > /tmp/broadcast_censor_edit_result.json << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "initial_track_count": $INITIAL_TRACKS,
    "current_track_count": $CURRENT_TRACKS,
    "track_names": "$TRACK_NAMES",
    "export_file_exists": $EXPORT_FILE_EXISTS,
    "export_file_path": "$EXPORT_FILE_PATH",
    "export_file_size": $EXPORT_FILE_SIZE,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/broadcast_censor_edit_result.json"
echo "=== Export Complete ==="