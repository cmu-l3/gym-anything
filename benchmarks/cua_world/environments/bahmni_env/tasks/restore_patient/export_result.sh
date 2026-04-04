#!/bin/bash
echo "=== Exporting Restore Patient Result ==="

source /workspace/scripts/task_utils.sh

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get Target Patient UUID
PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null || echo "")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Target patient UUID not found in /tmp/target_patient_uuid.txt"
    PATIENT_FOUND="false"
    IS_VOIDED="true" # Fail safe
    LAST_CHANGED=""
else
    PATIENT_FOUND="true"
    # Query OpenMRS for current state
    # Must use includeAll=true to see the patient regardless of void status
    API_RESP=$(openmrs_api_get "/patient/${PATIENT_UUID}?v=full&includeAll=true")
    
    # Extract data using python
    read IS_VOIDED DATE_CHANGED CHANGED_BY <<< $(echo "$API_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    voided = str(data.get('voided', 'true')).lower()
    # Audit info might be in 'auditInfo' object depending on OpenMRS version
    audit = data.get('auditInfo', {})
    date_changed = audit.get('dateChanged', '')
    changed_by = audit.get('changedBy', {}).get('display', '')
    print(f'{voided} {date_changed} {changed_by}')
except Exception:
    print('true  ')
")
fi

echo "Patient Status - Found: $PATIENT_FOUND, Voided: $IS_VOIDED, Changed: $DATE_CHANGED"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "task_end_ts": $TASK_END,
    "patient_uuid": "$PATIENT_UUID",
    "patient_found": $PATIENT_FOUND,
    "is_voided": $IS_VOIDED,
    "date_changed": "$DATE_CHANGED",
    "changed_by": "$CHANGED_BY",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="