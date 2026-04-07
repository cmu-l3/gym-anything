#!/bin/bash
# Export script for Process Medication Refill task

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PID=$(cat /tmp/patient_id.txt 2>/dev/null || echo "0")

# Fallback to query if PID file is missing
if [ "$PID" = "0" ] || [ -z "$PID" ]; then
    PID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Jenkins' LIMIT 1" 2>/dev/null || echo "0")
fi

echo "Evaluating prescriptions for Patient ID: $PID"

# Query the database for the LATEST refill count of each drug for this patient
# (Handles both in-place updates and creating a new prescription row for the renewal)
ATORVA_REFILLS=$(freemed_query "SELECT rxrefills FROM rx WHERE rxpatient=$PID AND LOWER(rxdrug) LIKE '%atorvastatin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
METFOR_REFILLS=$(freemed_query "SELECT rxrefills FROM rx WHERE rxpatient=$PID AND LOWER(rxdrug) LIKE '%metformin%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
LISINO_REFILLS=$(freemed_query "SELECT rxrefills FROM rx WHERE rxpatient=$PID AND LOWER(rxdrug) LIKE '%lisinopril%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Set defaults if not found
ATORVA_REFILLS=${ATORVA_REFILLS:-NOT_FOUND}
METFOR_REFILLS=${METFOR_REFILLS:-NOT_FOUND}
LISINO_REFILLS=${LISINO_REFILLS:-NOT_FOUND}

echo "Atorvastatin Refills: $ATORVA_REFILLS"
echo "Metformin Refills: $METFOR_REFILLS"
echo "Lisinopril Refills: $LISINO_REFILLS"

# Check if application was still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Generate JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_id": "$PID",
    "atorvastatin_refills": "$ATORVA_REFILLS",
    "metformin_refills": "$METFOR_REFILLS",
    "lisinopril_refills": "$LISINO_REFILLS",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="