#!/bin/bash
echo "=== Exporting reprocess_event_corrected_gain result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EVENT_ID=$(cat /tmp/event_id.txt 2>/dev/null || echo "")
INITIAL_MAG=$(cat /tmp/initial_mag.txt 2>/dev/null || echo "0")

if [ -z "$EVENT_ID" ]; then
    echo "No event ID found."
    NEW_MAG_EXISTS="false"
    NEW_MAG_VALUE=""
    NEW_AMPS_COUNT="0"
else
    ORIGIN_ID=$(mysql -u sysop -psysop seiscomp -N -e "SELECT preferredOriginID FROM Event WHERE publicID='$EVENT_ID';" 2>/dev/null)
    
    NEW_MAG_VALUE=""
    NEW_MAG_EXISTS="false"
    
    if [ -n "$ORIGIN_ID" ]; then
        # Check for any new magnitude linked to this origin created after task start
        NEW_MAG_DATA=$(mysql -u sysop -psysop seiscomp -N -e "SELECT magnitude_value FROM Magnitude WHERE originID='$ORIGIN_ID' AND UNIX_TIMESTAMP(creationInfo_creationTime) > $TASK_START ORDER BY creationInfo_creationTime DESC LIMIT 1;" 2>/dev/null)
        
        if [ -n "$NEW_MAG_DATA" ]; then
            NEW_MAG_VALUE=$NEW_MAG_DATA
            NEW_MAG_EXISTS="true"
        fi
    fi
    
    # Check for any amplitudes created after task start
    NEW_AMPS_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Amplitude WHERE UNIX_TIMESTAMP(creationInfo_creationTime) > $TASK_START;" 2>/dev/null || echo "0")
fi

APP_RUNNING="false"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "event_id": "$EVENT_ID",
    "initial_mag": $INITIAL_MAG,
    "new_mag_exists": $NEW_MAG_EXISTS,
    "new_mag_value": "$NEW_MAG_VALUE",
    "new_amps_count": $NEW_AMPS_COUNT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="