#!/bin/bash
echo "=== Exporting add_incident_location results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get Case ID
CASE_ID=$(cat /tmp/task_case_id.txt 2>/dev/null || echo "")

if [ -z "$CASE_ID" ]; then
    echo "ERROR: No Case ID found from setup."
    exit 0
fi

echo "Checking Case ID: $CASE_ID"

# Fetch Case Details (may contain locations directly)
echo "Fetching case details..."
CASE_JSON=$(arkcase_api GET "plugin/complaint/$CASE_ID")

# Fetch Locations explicitly (common sub-resource pattern)
echo "Fetching case locations..."
LOCATIONS_JSON=$(arkcase_api GET "plugin/complaint/$CASE_ID/locations")

# Fetch Object Associations (another way locations might be linked)
echo "Fetching associations..."
ASSOCIATIONS_JSON=$(arkcase_api GET "service/objectassociation/COMPLAINT/$CASE_ID/LOCATION")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "case_data": $CASE_JSON,
    "locations_data": ${LOCATIONS_JSON:-[]},
    "associations_data": ${ASSOCIATIONS_JSON:-[]},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="