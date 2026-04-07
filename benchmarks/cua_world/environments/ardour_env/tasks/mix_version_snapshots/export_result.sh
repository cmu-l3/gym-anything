#!/bin/bash
echo "=== Exporting mix_version_snapshots result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 2
    fi
    kill_ardour
fi

sleep 1

SESSION_DIR="/home/ga/Audio/sessions/MyProject"

# Find the specific snapshot files (case-insensitive, allowing slight variations)
FULL_MIX=$(find "$SESSION_DIR" -maxdepth 1 -type f -iname "*full*mix*.ardour" | head -1)
REDUCED_MIX=$(find "$SESSION_DIR" -maxdepth 1 -type f -iname "*reduced*mix*.ardour" | head -1)
MUTED_TRACK=$(find "$SESSION_DIR" -maxdepth 1 -type f -iname "*muted*track*.ardour" | head -1)

# Check creation times to ensure they were made during the task
check_freshness() {
    local file="$1"
    if [ -n "$file" ] && [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

FULL_MIX_FRESH=$(check_freshness "$FULL_MIX")
REDUCED_MIX_FRESH=$(check_freshness "$REDUCED_MIX")
MUTED_TRACK_FRESH=$(check_freshness "$MUTED_TRACK")

# Copy found snapshots to a predictable temporary location for the verifier
rm -f /tmp/Full_Mix_Snapshot.ardour /tmp/Reduced_Mix_Snapshot.ardour /tmp/Muted_Track_Snapshot.ardour 2>/dev/null || true

[ -n "$FULL_MIX" ] && cp "$FULL_MIX" /tmp/Full_Mix_Snapshot.ardour
[ -n "$REDUCED_MIX" ] && cp "$REDUCED_MIX" /tmp/Reduced_Mix_Snapshot.ardour
[ -n "$MUTED_TRACK" ] && cp "$MUTED_TRACK" /tmp/Muted_Track_Snapshot.ardour

# Generate result JSON
TEMP_JSON=$(mktemp /tmp/snapshot_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "full_mix": {
        "exists": $([ -n "$FULL_MIX" ] && echo "true" || echo "false"),
        "is_fresh": $FULL_MIX_FRESH,
        "path": "$FULL_MIX"
    },
    "reduced_mix": {
        "exists": $([ -n "$REDUCED_MIX" ] && echo "true" || echo "false"),
        "is_fresh": $REDUCED_MIX_FRESH,
        "path": "$REDUCED_MIX"
    },
    "muted_track": {
        "exists": $([ -n "$MUTED_TRACK" ] && echo "true" || echo "false"),
        "is_fresh": $MUTED_TRACK_FRESH,
        "path": "$MUTED_TRACK"
    }
}
EOF

# Make result available
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="