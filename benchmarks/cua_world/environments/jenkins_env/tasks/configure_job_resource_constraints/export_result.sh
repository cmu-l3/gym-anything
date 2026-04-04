#!/bin/bash
# Export script for Configure Job Resource Constraints task

echo "=== Exporting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

JOB_NAME="Legacy-Monolith-Build"
JOB_EXISTS="false"
CONCURRENT_BUILD="null"
QUIET_PERIOD="null"
ASSIGNED_NODE="null"

# Check if job exists
if job_exists "$JOB_NAME"; then
    JOB_EXISTS="true"
    echo "Job '$JOB_NAME' found."

    # Get config XML
    CONFIG_XML=$(get_job_config "$JOB_NAME")
    
    # Extract concurrentBuild (boolean)
    # XML format: <concurrentBuild>true</concurrentBuild> or <concurrentBuild>false</concurrentBuild>
    # Note: If missing, default depends on version, but usually false for new jobs, we explicitly set true in setup.
    CONCURRENT_BUILD=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//concurrentBuild" 2>/dev/null)
    
    # Extract quietPeriod (integer)
    # XML format: <quietPeriod>45</quietPeriod>
    QUIET_PERIOD=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//quietPeriod" 2>/dev/null)
    
    # Extract assignedNode (string)
    # XML format: <assignedNode>build-server-v2</assignedNode>
    ASSIGNED_NODE=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//assignedNode" 2>/dev/null)

    echo "Config extracted:"
    echo "  concurrentBuild: $CONCURRENT_BUILD"
    echo "  quietPeriod: $QUIET_PERIOD"
    echo "  assignedNode: $ASSIGNED_NODE"
else
    echo "Job '$JOB_NAME' NOT found."
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "job_exists": $JOB_EXISTS,
    "concurrent_build": "$CONCURRENT_BUILD",
    "quiet_period": "$QUIET_PERIOD",
    "assigned_node": "$ASSIGNED_NODE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="