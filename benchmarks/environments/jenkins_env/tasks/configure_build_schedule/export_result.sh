#!/bin/bash
# Export script for Configure Build Schedule task
# Checks if the job has a periodic build trigger configured

echo "=== Exporting Configure Build Schedule Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

JOB_NAME="Nightly-Backup"
JOB_FOUND="false"
HAS_TIMER_TRIGGER="false"
SCHEDULE_VALUE=""
TRIGGER_COUNT=0

# Check if job exists
echo "Checking for job '$JOB_NAME'..."
if job_exists "$JOB_NAME"; then
    JOB_FOUND="true"
    echo "Job '$JOB_NAME' found!"

    # Get job configuration XML
    JOB_CONFIG=$(get_job_config "$JOB_NAME" 2>/dev/null)

    if [ -n "$JOB_CONFIG" ]; then
        # Check for TimerTrigger (periodic build trigger)
        TIMER_CHECK=$(echo "$JOB_CONFIG" | grep -c "hudson.triggers.TimerTrigger" || true)
        if [ "$TIMER_CHECK" -gt 0 ]; then
            HAS_TIMER_TRIGGER="true"
            echo "TimerTrigger found in job config"

            # Extract the schedule spec
            SCHEDULE_VALUE=$(echo "$JOB_CONFIG" | xmlstarlet sel -t -v "//hudson.triggers.TimerTrigger/spec" 2>/dev/null || echo "")
            if [ -z "$SCHEDULE_VALUE" ]; then
                # Fallback: grep method
                SCHEDULE_VALUE=$(echo "$JOB_CONFIG" | grep -A1 "TimerTrigger" | grep "<spec>" | sed 's/.*<spec>\(.*\)<\/spec>.*/\1/' 2>/dev/null || echo "")
            fi
            echo "Schedule value: '$SCHEDULE_VALUE'"
        else
            echo "No TimerTrigger found in job config"
        fi

        # Count all trigger types (opening tags only to avoid double-counting)
        TRIGGER_COUNT=$(echo "$JOB_CONFIG" | grep -c "<hudson\.triggers\.[^/]" || true)
        echo "Total trigger count: $TRIGGER_COUNT"
    fi
else
    echo "Job '$JOB_NAME' NOT found"
fi

# Create JSON using jq
TEMP_JSON=$(mktemp /tmp/configure_build_schedule_result.XXXXXX.json)
jq -n \
    --argjson job_found "$JOB_FOUND" \
    --argjson has_timer_trigger "$HAS_TIMER_TRIGGER" \
    --arg job_name "$JOB_NAME" \
    --arg schedule "$SCHEDULE_VALUE" \
    --argjson trigger_count "${TRIGGER_COUNT:-0}" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        job_found: $job_found,
        job_name: $job_name,
        has_timer_trigger: $has_timer_trigger,
        schedule: $schedule,
        trigger_count: $trigger_count,
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

rm -f /tmp/configure_build_schedule_result.json 2>/dev/null || sudo rm -f /tmp/configure_build_schedule_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_build_schedule_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/configure_build_schedule_result.json
chmod 666 /tmp/configure_build_schedule_result.json 2>/dev/null || sudo chmod 666 /tmp/configure_build_schedule_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/configure_build_schedule_result.json"
cat /tmp/configure_build_schedule_result.json

echo ""
echo "=== Export Complete ==="
