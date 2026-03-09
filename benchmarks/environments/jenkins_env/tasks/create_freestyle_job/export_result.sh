#!/bin/bash
# Export script for Create Freestyle Job task
# Saves all verification data to JSON file for verifier to read

echo "=== Exporting Create Freestyle Job Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current job count
CURRENT_COUNT=$(count_jobs)
INITIAL_COUNT=$(cat /tmp/initial_job_count 2>/dev/null || echo "0")

echo "Job count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Debug: List all jobs
echo ""
echo "=== DEBUG: All jobs in Jenkins ==="
list_jobs
echo "=== END DEBUG ==="
echo ""

# Check if the target job was created (case-insensitive)
echo "Checking for job 'HelloWorld-Build'..."
JOB_FOUND="false"
JOB_NAME=""
JOB_CONFIG=""
BUILD_COMMAND=""

# Try exact match first
if job_exists "HelloWorld-Build"; then
    JOB_FOUND="true"
    JOB_NAME="HelloWorld-Build"
    echo "Job 'HelloWorld-Build' found!"
elif job_exists "helloworld-build"; then
    JOB_FOUND="true"
    JOB_NAME="helloworld-build"
    echo "Job 'helloworld-build' found!"
elif job_exists "HelloWorld-build"; then
    JOB_FOUND="true"
    JOB_NAME="HelloWorld-build"
    echo "Job 'HelloWorld-build' found!"
else
    # Check if any job with "hello" in name was created
    ALL_JOBS=$(list_jobs)
    HELLO_JOB=$(echo "$ALL_JOBS" | grep -i "hello" | head -1)
    if [ -n "$HELLO_JOB" ]; then
        JOB_FOUND="true"
        JOB_NAME="$HELLO_JOB"
        echo "Found job with 'hello' in name: $JOB_NAME"
    else
        # Check if any new job was created
        if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
            # Get the newest job (last in list)
            NEW_JOB=$(echo "$ALL_JOBS" | tail -1)
            if [ -n "$NEW_JOB" ]; then
                JOB_FOUND="true"
                JOB_NAME="$NEW_JOB"
                echo "Found new job (not matching expected name): $JOB_NAME"
            fi
        fi
    fi
fi

# Get job configuration if found
if [ "$JOB_FOUND" = "true" ] && [ -n "$JOB_NAME" ]; then
    echo "Fetching job configuration for: $JOB_NAME"
    JOB_CONFIG=$(get_job_config "$JOB_NAME" 2>/dev/null)

    # Extract build command from config XML
    # Look for shell command in <hudson.tasks.Shell> section
    if [ -n "$JOB_CONFIG" ]; then
        BUILD_COMMAND=$(echo "$JOB_CONFIG" | xmlstarlet sel -t -v "//hudson.tasks.Shell/command" 2>/dev/null || echo "")
        if [ -z "$BUILD_COMMAND" ]; then
            # Fallback: try grep method
            BUILD_COMMAND=$(echo "$JOB_CONFIG" | grep -A 1 "<command>" | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")
        fi
        echo "Extracted build command: $BUILD_COMMAND"
    fi
else
    echo "Job 'HelloWorld-Build' NOT found in Jenkins"
fi

# Create JSON using jq for safe escaping of special characters
TEMP_JSON=$(mktemp /tmp/create_freestyle_job_result.XXXXXX.json)
jq -n \
    --argjson initial_count "${INITIAL_COUNT:-0}" \
    --argjson current_count "${CURRENT_COUNT:-0}" \
    --argjson job_found "$JOB_FOUND" \
    --arg job_name "$JOB_NAME" \
    --arg build_command "$BUILD_COMMAND" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        initial_job_count: $initial_count,
        current_job_count: $current_count,
        job_found: $job_found,
        job: {
            name: $job_name,
            build_command: $build_command
        },
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move temp file to final location (handles permission issues)
rm -f /tmp/create_freestyle_job_result.json 2>/dev/null || sudo rm -f /tmp/create_freestyle_job_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_freestyle_job_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_freestyle_job_result.json
chmod 666 /tmp/create_freestyle_job_result.json 2>/dev/null || sudo chmod 666 /tmp/create_freestyle_job_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_freestyle_job_result.json"
cat /tmp/create_freestyle_job_result.json

echo ""
echo "=== Export Complete ==="
