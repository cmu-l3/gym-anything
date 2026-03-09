#!/bin/bash
# Export script for Configure Shared Library task
# Extracts system config and job config for verification

echo "=== Exporting Configure Shared Library Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# 1. Export Global Library Configuration
# ==============================================================================
echo "Exporting GlobalLibraries.xml..."
LIB_CONFIG_PATH="/tmp/GlobalLibraries.xml"
rm -f "$LIB_CONFIG_PATH"

# Copy the config file from the Docker container
if docker cp jenkins-server:/var/jenkins_home/org.jenkinsci.plugins.workflow.libs.GlobalLibraries.xml "$LIB_CONFIG_PATH" 2>/dev/null; then
    LIB_CONFIG_EXISTS="true"
    # Get file modification time from inside the container
    LIB_MTIME_ISO=$(docker exec jenkins-server stat -c %y /var/jenkins_home/org.jenkinsci.plugins.workflow.libs.GlobalLibraries.xml 2>/dev/null)
    LIB_MTIME=$(date -d "$LIB_MTIME_ISO" +%s 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$LIB_MTIME" -gt "$TASK_START" ]; then
        LIB_MODIFIED_DURING_TASK="true"
    else
        LIB_MODIFIED_DURING_TASK="false"
    fi
    
    # Read content for JSON inclusion (escape quotes)
    LIB_CONFIG_CONTENT=$(cat "$LIB_CONFIG_PATH" | jq -sR .)
else
    echo "GlobalLibraries.xml not found in container."
    LIB_CONFIG_EXISTS="false"
    LIB_MODIFIED_DURING_TASK="false"
    LIB_CONFIG_CONTENT="null"
fi

# ==============================================================================
# 2. Export Job Configuration
# ==============================================================================
JOB_NAME="shared-lib-test"
echo "Checking for job '$JOB_NAME'..."

JOB_EXISTS="false"
JOB_CREATED_DURING_TASK="false"
JOB_CONFIG_CONTENT="null"
JOB_CLASS=""

if job_exists "$JOB_NAME"; then
    JOB_EXISTS="true"
    
    # Get Job Config XML
    RAW_JOB_CONFIG=$(get_job_config "$JOB_NAME")
    JOB_CONFIG_CONTENT=$(echo "$RAW_JOB_CONFIG" | jq -sR .)
    
    # Get Job Info JSON
    JOB_INFO=$(jenkins_api "job/${JOB_NAME}/api/json" 2>/dev/null)
    JOB_CLASS=$(echo "$JOB_INFO" | jq -r '._class // empty')
    
    # Check creation/modification time via build history or assumption
    # Since we deleted it in setup, existence implies creation during task,
    # but strictly we can check the job directory creation time if needed.
    # For now, we assume true if it exists because we deleted it in setup.
    JOB_CREATED_DURING_TASK="true" 
fi

# ==============================================================================
# 3. Create Result JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/shared_lib_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "lib_config_exists": $LIB_CONFIG_EXISTS,
    "lib_modified_during_task": $LIB_MODIFIED_DURING_TASK,
    "lib_config_content": $LIB_CONFIG_CONTENT,
    "job_exists": $JOB_EXISTS,
    "job_created_during_task": $JOB_CREATED_DURING_TASK,
    "job_class": "$JOB_CLASS",
    "job_config_content": $JOB_CONFIG_CONTENT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
rm -f /tmp/shared_lib_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/shared_lib_result.json
chmod 666 /tmp/shared_lib_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/shared_lib_result.json"