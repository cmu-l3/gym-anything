#!/bin/bash
echo "=== Exporting update_patient_demographics result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PATIENT_GUID=$(cat /tmp/task_patient_guid.txt 2>/dev/null)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$PATIENT_GUID" ]; then
    echo "ERROR: Patient GUID not found from setup"
    PATIENT_FOUND="false"
else
    PATIENT_FOUND="true"
fi

# Query current database state for the patient
echo "Querying database for GUID: $PATIENT_GUID"

# Use safe separator for SQL output to handle spaces/newlines
SQL_RESULT=$(mysql -u root DrTuxTest -N -e "SELECT FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_DatModif FROM fchpat WHERE FchPat_GUID_Doss='$PATIENT_GUID'" 2>/dev/null)

if [ -z "$SQL_RESULT" ]; then
    PATIENT_FOUND="false"
    ADDR=""
    CP=""
    VILLE=""
    TEL=""
    MODIF=""
else
    # Parse tab-separated output
    ADDR=$(echo "$SQL_RESULT" | awk -F'\t' '{print $1}')
    CP=$(echo "$SQL_RESULT" | awk -F'\t' '{print $2}')
    VILLE=$(echo "$SQL_RESULT" | awk -F'\t' '{print $3}')
    TEL=$(echo "$SQL_RESULT" | awk -F'\t' '{print $4}')
    MODIF=$(echo "$SQL_RESULT" | awk -F'\t' '{print $5}')
fi

# Check if MedinTux Manager was running (anti-gaming)
# We check if it's running NOW or if we can see it in process history (simulated by checking if it's running now)
if pgrep -f "Manager.exe" > /dev/null 2>&1; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
else
    SCREENSHOT_EXISTS="false"
fi

# Escape JSON strings
ADDR_ESC=$(echo "$ADDR" | sed 's/"/\\"/g')
VILLE_ESC=$(echo "$VILLE" | sed 's/"/\\"/g')
TEL_ESC=$(echo "$TEL" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_found": $PATIENT_FOUND,
    "patient_guid": "$PATIENT_GUID",
    "final_address": "$ADDR_ESC",
    "final_cp": "$CP",
    "final_city": "$VILLE_ESC",
    "final_phone": "$TEL_ESC",
    "last_modified": "$MODIF",
    "app_was_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="