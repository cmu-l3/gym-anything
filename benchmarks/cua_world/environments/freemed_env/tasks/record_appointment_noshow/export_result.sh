#!/bin/bash
echo "=== Exporting record_appointment_noshow result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_export_final.png

# Read initial state using python to avoid jq dependency issues
APP_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('appointment_id', ''))" 2>/dev/null)
INIT_STATUS=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_status', ''))" 2>/dev/null)
PAT_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('patient_id', ''))" 2>/dev/null)

FINAL_STATUS=""
APPOINTMENT_EXISTS="false"

# Query current database state for the appointment
if [ -n "$APP_ID" ]; then
    # Check if it still exists
    COUNT=$(freemed_query "SELECT COUNT(*) FROM scheduler WHERE id='$APP_ID'" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt "0" ]; then
        APPOINTMENT_EXISTS="true"
        FINAL_STATUS=$(freemed_query "SELECT calstatus FROM scheduler WHERE id='$APP_ID'" 2>/dev/null)
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/noshow_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PAT_ID",
    "appointment_id": "$APP_ID",
    "initial_status": "$INIT_STATUS",
    "final_status": "$FINAL_STATUS",
    "appointment_exists": $APPOINTMENT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/noshow_result.json 2>/dev/null || sudo rm -f /tmp/noshow_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/noshow_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/noshow_result.json
chmod 666 /tmp/noshow_result.json 2>/dev/null || sudo chmod 666 /tmp/noshow_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/noshow_result.json"
cat /tmp/noshow_result.json

echo "=== Export complete ==="