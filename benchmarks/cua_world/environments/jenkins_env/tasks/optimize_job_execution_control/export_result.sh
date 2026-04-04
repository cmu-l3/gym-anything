#!/bin/bash
# Export script for Optimize Job Execution Control task

echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

JOB_NAME="Docs-Site-Gen"
RESULT_FILE="/tmp/task_result.json"

# Check if job exists
if ! job_exists "$JOB_NAME"; then
    echo "Job '$JOB_NAME' not found!"
    echo '{"job_exists": false}' > "$RESULT_FILE"
    exit 0
fi

# Get Job Config API JSON
# This returns the current state properties
JOB_API_JSON=$(jenkins_api "job/$JOB_NAME/api/json?pretty=true" 2>/dev/null)

# Get Job Config XML for deeper verification (sometimes API doesn't show quietPeriod if it matches system default, but we want to check if it IS 60)
JOB_XML=$(get_job_config "$JOB_NAME" 2>/dev/null)

# Extract values using jq from API
# concurrentBuild: boolean
CONCURRENT_BUILD=$(echo "$JOB_API_JSON" | jq -r '.concurrentBuild')

# quietPeriod: integer (might be null if not set)
# In API, if quietPeriod is not set, it might return null or the system default.
# Let's check API first.
QUIET_PERIOD=$(echo "$JOB_API_JSON" | jq -r '.quietPeriod // "null"')

# If API returns null, check XML
if [ "$QUIET_PERIOD" == "null" ]; then
    # Parse XML for <quietPeriod> tag
    QUIET_PERIOD_XML=$(echo "$JOB_XML" | grep -oP '(?<=<quietPeriod>)\d+(?=</quietPeriod>)' || echo "null")
    if [ "$QUIET_PERIOD_XML" != "null" ]; then
        QUIET_PERIOD=$QUIET_PERIOD_XML
    fi
fi

echo "Extracted Config:"
echo "  concurrentBuild: $CONCURRENT_BUILD"
echo "  quietPeriod: $QUIET_PERIOD"

# Create result JSON
# Note: jq handles boolean literals correctly
jq -n \
    --argjson job_exists true \
    --argjson concurrent_build "$CONCURRENT_BUILD" \
    --argjson quiet_period "${QUIET_PERIOD:-0}" \
    --arg job_name "$JOB_NAME" \
    '{
        job_exists: $job_exists,
        job_name: $job_name,
        concurrent_build: $concurrent_build,
        quiet_period: $quiet_period,
        timestamp: now
    }' > "$RESULT_FILE"

# Move to final location
rm -f /tmp/optimize_job_result.json 2>/dev/null || true
cp "$RESULT_FILE" /tmp/optimize_job_result.json
chmod 666 /tmp/optimize_job_result.json 2>/dev/null || true

echo "Result saved to /tmp/optimize_job_result.json"
cat /tmp/optimize_job_result.json