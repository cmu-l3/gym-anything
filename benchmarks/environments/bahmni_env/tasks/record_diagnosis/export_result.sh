#!/bin/bash
echo "=== Exporting record_diagnosis results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve Verification Data
PATIENT_UUID=$(cat /tmp/patient_uuid.txt 2>/dev/null || echo "")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_DIAGNOSES_FILE="/tmp/initial_diagnoses.json"

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Patient UUID missing."
    # Try to recover it
    PATIENT_UUID=$(get_patient_uuid_by_identifier "BAH000005")
fi

echo "Fetching final diagnoses for patient $PATIENT_UUID..."

# Query Bahmni Diagnosis API
# This endpoint returns the specific structure used by the Clinical app
FINAL_DIAGNOSES_JSON=$(openmrs_api_get "/bahmnicore/diagnosis/search?patientUuid=${PATIENT_UUID}")

# 3. Construct Result JSON
# We embed both the API response and the task start time for the Python verifier to process.
# We also include the initial diagnoses to filter out pre-existing ones if needed (though timestamp check is better).

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "patient_uuid": "$PATIENT_UUID",
    "final_diagnoses": $FINAL_DIAGNOSES_JSON,
    "initial_diagnoses_file_exists": $([ -f "$INITIAL_DIAGNOSES_FILE" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="