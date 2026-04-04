#!/bin/bash
# Export script for Register Restored Job task
# Verifies job visibility, build status, and ensures no restart occurred

echo "=== Exporting Register Restored Job Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target Job Name
JOB_NAME="Legacy-Payroll"

# --- 1. Check if Job is Now Visible in API ---
JOB_VISIBLE="false"
if job_exists "$JOB_NAME"; then
    JOB_VISIBLE="true"
    echo "Job '$JOB_NAME' is visible in API."
else
    echo "Job '$JOB_NAME' is NOT visible in API."
fi

# --- 2. Check Build Status ---
BUILD_EXISTS="false"
BUILD_SUCCESS="false"
BUILD_NUMBER=0

if [ "$JOB_VISIBLE" = "true" ]; then
    # Get last build status
    LAST_BUILD_JSON=$(jenkins_api "job/$JOB_NAME/lastBuild/api/json" 2>/dev/null)
    
    if [ -n "$LAST_BUILD_JSON" ] && echo "$LAST_BUILD_JSON" | grep -q '"number"'; then
        BUILD_EXISTS="true"
        BUILD_NUMBER=$(echo "$LAST_BUILD_JSON" | jq -r '.number' 2>/dev/null)
        RESULT=$(echo "$LAST_BUILD_JSON" | jq -r '.result' 2>/dev/null)
        
        echo "Found build #$BUILD_NUMBER with result: $RESULT"
        
        if [ "$RESULT" = "SUCCESS" ]; then
            BUILD_SUCCESS="true"
        fi
    else
        echo "No builds found for '$JOB_NAME'."
    fi
fi

# --- 3. Anti-Gaming: Restart Detection ---
# We check if the PID of the Jenkins process has changed or if uptime is too short
RESTART_DETECTED="false"

# Check 1: PID comparison
INITIAL_PID=$(cat /tmp/initial_jenkins_pid.txt 2>/dev/null || echo "0")
CURRENT_PID=$(docker exec jenkins-docker pgrep -f "jenkins.war" | head -1 || echo "-1")

echo "PID Check: Initial=$INITIAL_PID, Current=$CURRENT_PID"

if [ "$INITIAL_PID" != "$CURRENT_PID" ]; then
    RESTART_DETECTED="true"
    echo "Restart detected: Process ID changed."
fi

# Check 2: Container uptime (backup check)
# Get container started time in epoch
CONTAINER_START=$(docker inspect --format='{{.State.StartedAt}}' jenkins-docker | date -f - +%s 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Time Check: ContainerStart=$CONTAINER_START, TaskStart=$TASK_START"

if [ "$CONTAINER_START" -gt "$TASK_START" ]; then
    RESTART_DETECTED="true"
    echo "Restart detected: Container restarted after task began."
fi

# --- 4. Export JSON ---
TEMP_JSON=$(mktemp /tmp/restored_job_result.XXXXXX.json)
jq -n \
    --argjson job_visible "$JOB_VISIBLE" \
    --argjson build_exists "$BUILD_EXISTS" \
    --argjson build_success "$BUILD_SUCCESS" \
    --argjson restart_detected "$RESTART_DETECTED" \
    --arg job_name "$JOB_NAME" \
    --arg initial_pid "$INITIAL_PID" \
    --arg current_pid "$CURRENT_PID" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        job_visible: $job_visible,
        build_exists: $build_exists,
        build_success: $build_success,
        restart_detected: $restart_detected,
        job_name: $job_name,
        debug: {
            initial_pid: $initial_pid,
            current_pid: $current_pid
        },
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move to final location
sudo mv "$TEMP_JSON" /tmp/restored_job_result.json
sudo chmod 666 /tmp/restored_job_result.json

echo "Result JSON content:"
cat /tmp/restored_job_result.json
echo "=== Export Complete ==="