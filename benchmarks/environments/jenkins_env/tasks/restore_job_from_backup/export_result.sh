#!/bin/bash
# Export script for Restore Job task
# Checks if job exists and verifies its configuration matches the backup

echo "=== Exporting Restore Job Result ==="

source /workspace/scripts/task_utils.sh

JOB_NAME="Production-Deploy-Pipeline"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if job exists
JOB_EXISTS="false"
if job_exists "$JOB_NAME"; then
    JOB_EXISTS="true"
    echo "Job '$JOB_NAME' found."
else
    echo "Job '$JOB_NAME' NOT found."
fi

# 2. Get Job Class/Type
JOB_CLASS=""
if [ "$JOB_EXISTS" = "true" ]; then
    JOB_CLASS=$(jenkins_api "job/$JOB_NAME/api/json" | jq -r '._class' 2>/dev/null)
    echo "Job Class: $JOB_CLASS"
fi

# 3. Get Job Configuration for deep inspection
JOB_CONFIG=""
HAS_PIPELINE_SCRIPT="false"
HAS_PARAM_DEPLOY="false"
HAS_PARAM_BUILD="false"
HAS_SCM_TRIGGER="false"
HAS_LOG_ROTATOR="false"
LOG_ROTATOR_NUM="0"

if [ "$JOB_EXISTS" = "true" ]; then
    JOB_CONFIG=$(get_job_config "$JOB_NAME")
    
    # Check for Pipeline script content
    if echo "$JOB_CONFIG" | grep -q "simple-java-maven-app"; then
        HAS_PIPELINE_SCRIPT="true"
    fi
    
    # Check for Parameters
    if echo "$JOB_CONFIG" | grep -q "DEPLOY_ENV"; then
        HAS_PARAM_DEPLOY="true"
    fi
    if echo "$JOB_CONFIG" | grep -q "BUILD_TYPE"; then
        HAS_PARAM_BUILD="true"
    fi
    
    # Check for SCM Trigger (H/15 * * * *)
    if echo "$JOB_CONFIG" | grep -q "H/15 \* \* \* \*"; then
        HAS_SCM_TRIGGER="true"
    fi
    
    # Check for Log Rotator
    if echo "$JOB_CONFIG" | grep -q "BuildDiscarderProperty"; then
        HAS_LOG_ROTATOR="true"
        # Extract numToKeep
        LOG_ROTATOR_NUM=$(echo "$JOB_CONFIG" | xmlstarlet sel -t -v "//numToKeep" 2>/dev/null || echo "0")
    fi
fi

# 4. Anti-gaming: Check if job was created after task start
# We can check the job's creation time via the file system if we are root,
# or infer it from the fact it didn't exist at start (which setup_task ensures).
# Since we deleted it in setup, and it exists now, it must have been created.
# We'll just pass a flag saying it was restored.
JOB_RESTORED="false"
if [ "$JOB_EXISTS" = "true" ]; then
    JOB_RESTORED="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/restore_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "job_exists": $JOB_EXISTS,
    "job_name": "$JOB_NAME",
    "job_class": "$JOB_CLASS",
    "config_verification": {
        "has_pipeline_script": $HAS_PIPELINE_SCRIPT,
        "has_param_deploy": $HAS_PARAM_DEPLOY,
        "has_param_build": $HAS_PARAM_BUILD,
        "has_scm_trigger": $HAS_SCM_TRIGGER,
        "has_log_rotator": $HAS_LOG_ROTATOR,
        "log_rotator_num": "$LOG_ROTATOR_NUM"
    },
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move and set permissions
rm -f /tmp/restore_job_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/restore_job_result.json
chmod 666 /tmp/restore_job_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/restore_job_result.json"
cat /tmp/restore_job_result.json
echo "=== Export Complete ==="