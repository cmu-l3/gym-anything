#!/bin/bash
# Export script for Annotate and Pin Release Build task

echo "=== Exporting Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

JOB_NAME="regression-test-suite"
TARGET_BUILD=3

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if job exists
if ! job_exists "$JOB_NAME"; then
    echo "ERROR: Job '$JOB_NAME' missing"
    # Dump empty failure result
    cat > /tmp/annotate_pin_result.json <<EOF
{
    "job_exists": false,
    "builds": [],
    "error": "Job deleted or missing"
}
EOF
    exit 0
fi

# Get detailed info for all builds
# We use depth=1 to get build details (actions, description, keepLog, displayName)
echo "Fetching build details..."
JSON_RESPONSE=$(jenkins_api "job/$JOB_NAME/api/json?depth=1")

# Extract relevant fields using jq
# We structure the output to map build numbers to their metadata
# We specifically look for:
# - number
# - keepLog (is it pinned?)
# - description
# - displayName
# - fullDisplayName
echo "$JSON_RESPONSE" | jq '{
    job_exists: true,
    job_name: .name,
    builds: [.builds[] | {
        number: .number,
        keepLog: .keepLog,
        description: .description,
        displayName: .displayName,
        fullDisplayName: .fullDisplayName,
        timestamp: .timestamp
    }]
}' > /tmp/annotate_pin_result.json

# Add task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Merge timing into result
jq --arg start "$TASK_START" --arg end "$TASK_END" \
   '. + {task_start: $start, task_end: $end}' \
   /tmp/annotate_pin_result.json > /tmp/annotate_pin_result.tmp && mv /tmp/annotate_pin_result.tmp /tmp/annotate_pin_result.json

# Set permissions
chmod 666 /tmp/annotate_pin_result.json

echo "Result saved to /tmp/annotate_pin_result.json"
cat /tmp/annotate_pin_result.json
echo "=== Export Complete ==="