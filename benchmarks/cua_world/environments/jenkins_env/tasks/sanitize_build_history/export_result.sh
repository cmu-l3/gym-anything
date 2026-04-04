#!/bin/bash
# Export script for Sanitize Build History task

echo "=== Exporting Sanitize Build History Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

JOB_NAME="payment-gateway-ci"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if job still exists
if job_exists "$JOB_NAME"; then
    JOB_EXISTS="true"
    
    # Get list of remaining build numbers
    # API returns builds array: [{number: 6, ...}, {number: 5, ...}]
    BUILDS_JSON=$(jenkins_api "job/${JOB_NAME}/api/json?tree=builds[number]")
    
    # Extract just the numbers into a JSON array [6, 5, 3, 1]
    REMAINING_BUILDS=$(echo "$BUILDS_JSON" | jq -r '[.builds[].number] | sort')
    
    # Get total count
    REMAINING_COUNT=$(echo "$BUILDS_JSON" | jq -r '.builds | length')
else
    JOB_EXISTS="false"
    REMAINING_BUILDS="[]"
    REMAINING_COUNT="0"
fi

# Capture timestamp
TIMESTAMP=$(date -Iseconds)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "job_exists": $JOB_EXISTS,
    "job_name": "$JOB_NAME",
    "remaining_builds": $REMAINING_BUILDS,
    "remaining_count": $REMAINING_COUNT,
    "export_timestamp": "$TIMESTAMP"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export Complete ==="