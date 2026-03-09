#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting copy_customize_job results ==="

RESULT_FILE="/tmp/copy_customize_job_result.json"
TARGET_JOB="Regression-Test-Runner"
SOURCE_JOB="Smoke-Test-Runner"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Analyze Target Job (Regression-Test-Runner)
REGRESSION_EXISTS="false"
REGRESSION_CLASS="unknown"
REGRESSION_DESC=""
REGRESSION_CMD=""
REGRESSION_CONFIG=""

if job_exists "$TARGET_JOB"; then
    REGRESSION_EXISTS="true"
    
    # Get Config XML
    REGRESSION_CONFIG=$(get_job_config "$TARGET_JOB" 2>/dev/null || echo "")
    
    # Get Class (Job Type)
    REGRESSION_CLASS=$(jenkins_api "job/${TARGET_JOB}/api/json" 2>/dev/null | jq -r '._class // "unknown"')
    
    # Extract Description
    REGRESSION_DESC=$(echo "$REGRESSION_CONFIG" | xmlstarlet sel -t -v "//project/description" 2>/dev/null || echo "")
    
    # Extract Shell Command
    # Try xmlstarlet first
    REGRESSION_CMD=$(echo "$REGRESSION_CONFIG" | xmlstarlet sel -t -v "//project/builders/hudson.tasks.Shell/command" 2>/dev/null || echo "")
    
    # Fallback to grep if xml extraction fails (sometimes namespaces get tricky)
    if [ -z "$REGRESSION_CMD" ]; then
        REGRESSION_CMD=$(echo "$REGRESSION_CONFIG" | grep -A 5 "<command>" | sed -n 's/.*<command>\(.*\)<\/command>.*/\1/p' | head -1)
    fi
fi

# 2. Analyze Source Job (Smoke-Test-Runner)
# We need to verify it still exists and hasn't been modified/renamed
SMOKE_EXISTS="false"
if job_exists "$SOURCE_JOB"; then
    SMOKE_EXISTS="true"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
# Using jq to safely build JSON with potentially multiline strings
jq -n \
    --arg reg_exists "$REGRESSION_EXISTS" \
    --arg reg_class "$REGRESSION_CLASS" \
    --arg reg_desc "$REGRESSION_DESC" \
    --arg reg_cmd "$REGRESSION_CMD" \
    --arg smoke_exists "$SMOKE_EXISTS" \
    --arg start_time "$TASK_START" \
    --arg end_time "$TASK_END" \
    '{
        regression_job_exists: ($reg_exists == "true"),
        regression_job_class: $reg_class,
        regression_description: $reg_desc,
        regression_command: $reg_cmd,
        smoke_job_exists: ($smoke_exists == "true"),
        task_start_time: $start_time,
        task_end_time: $end_time,
        screenshot_path: "/tmp/task_final.png"
    }' > "$RESULT_FILE"

echo "Results exported to $RESULT_FILE"
cat "$RESULT_FILE"