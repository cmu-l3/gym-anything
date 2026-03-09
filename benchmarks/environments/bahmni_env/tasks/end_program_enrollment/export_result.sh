#!/bin/bash
echo "=== Exporting End Program Enrollment Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Load target data
ENROLLMENT_UUID=$(cat /tmp/target_enrollment_uuid.txt 2>/dev/null || echo "")
PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null || echo "")

if [ -z "$ENROLLMENT_UUID" ]; then
  echo "ERROR: No target enrollment UUID found (setup failed?)"
  # Create empty failure result
  echo '{"error": "setup_failed"}' > /tmp/task_result.json
  exit 0
fi

# Query current state of the enrollment
log "Querying enrollment status for UUID: $ENROLLMENT_UUID"
API_RESPONSE=$(openmrs_api_get "/patientprogram/$ENROLLMENT_UUID?v=full")

# Extract fields
DATE_COMPLETED=$(echo "$API_RESPONSE" | jq -r '.dateCompleted // empty')
DATE_ENROLLED=$(echo "$API_RESPONSE" | jq -r '.dateEnrolled // empty')
PROGRAM_NAME=$(echo "$API_RESPONSE" | jq -r '.program.name // empty')
PATIENT_DISPLAY=$(echo "$API_RESPONSE" | jq -r '.patient.display // empty')
VOIDED=$(echo "$API_RESPONSE" | jq -r '.voided // false')

# Check today's date (YYYY-MM-DD)
TODAY=$(date +"%Y-%m-%d")

# Create JSON Result
cat > /tmp/task_result.json <<EOF
{
  "target_enrollment_uuid": "$ENROLLMENT_UUID",
  "program_name": "$PROGRAM_NAME",
  "date_enrolled": "$DATE_ENROLLED",
  "date_completed": "$DATE_COMPLETED",
  "today_date": "$TODAY",
  "is_voided": $VOIDED,
  "patient_uuid": "$PATIENT_UUID",
  "task_timestamp": "$(date -Iseconds)"
}
EOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Exported Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="