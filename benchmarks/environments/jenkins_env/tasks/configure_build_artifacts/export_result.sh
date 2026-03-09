#!/bin/bash
# Export script for Configure Build Artifacts task

echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

JOB_NAME="Integration-Tests"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check if job exists
if ! job_exists "$JOB_NAME"; then
    echo "Job '$JOB_NAME' not found!"
    # Write failure result
    cat > /tmp/task_result.json << EOF
{
    "job_exists": false,
    "config_changed": false,
    "log_rotator": null,
    "artifact_archiver": null,
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    exit 0
fi

# Get current config
CURRENT_CONFIG=$(get_job_config "$JOB_NAME")

# Extract Log Rotator settings using xmlstarlet
# Namespace handling in xmlstarlet can be tricky with Jenkins default namespace, so we use generic matching or sed if needed.
# Jenkins config usually sets xmlns which requires -N to xmlstarlet, but straightforward path often works if we ignore ns.

# Extract Days to keep
DAYS_TO_KEEP=$(echo "$CURRENT_CONFIG" | xmlstarlet sel -t -v "//jenkins.model.BuildDiscarderProperty/strategy/daysToKeep" 2>/dev/null || echo "")
# Extract Num to keep
NUM_TO_KEEP=$(echo "$CURRENT_CONFIG" | xmlstarlet sel -t -v "//jenkins.model.BuildDiscarderProperty/strategy/numToKeep" 2>/dev/null || echo "")

# Extract Artifact Archiver settings
ARTIFACTS_VAL=$(echo "$CURRENT_CONFIG" | xmlstarlet sel -t -v "//hudson.tasks.ArtifactArchiver/artifacts" 2>/dev/null || echo "")

# Check if config changed (simple string comparison against original)
ORIGINAL_CONFIG=$(cat /tmp/original_job_config.xml 2>/dev/null || echo "")
if [ "$CURRENT_CONFIG" != "$ORIGINAL_CONFIG" ]; then
    CONFIG_CHANGED="true"
else
    CONFIG_CHANGED="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --argjson job_exists true \
    --argjson config_changed "$CONFIG_CHANGED" \
    --arg days_keep "$DAYS_TO_KEEP" \
    --arg num_keep "$NUM_TO_KEEP" \
    --arg artifacts "$ARTIFACTS_VAL" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        job_exists: $job_exists,
        config_changed: $config_changed,
        log_rotator: {
            days_to_keep: $days_keep,
            num_to_keep: $num_keep
        },
        artifact_archiver: {
            artifacts: $artifacts
        },
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="