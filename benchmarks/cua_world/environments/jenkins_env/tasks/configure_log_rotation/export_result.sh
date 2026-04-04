#!/bin/bash
# Export script for Configure Log Rotation task

echo "=== Exporting Configure Log Rotation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

JOBS=("nightly-integration-tests" "feature-branch-builds" "release-pipeline")
JSON_PARTS=""

for JOB_NAME in "${JOBS[@]}"; do
    echo "Processing $JOB_NAME..."
    
    # Get Config XML
    CONFIG_XML=$(get_job_config "$JOB_NAME")
    
    # Check if log rotation exists in XML
    # Standard format: <jenkins.model.BuildDiscarderProperty><strategy class="hudson.tasks.LogRotator">
    HAS_ROTATOR="false"
    if echo "$CONFIG_XML" | grep -q "hudson.tasks.LogRotator"; then
        HAS_ROTATOR="true"
    fi
    
    # Extract values using xmlstarlet
    # Default to -1 if not found (Jenkins behavior for blank fields)
    DAYS_TO_KEEP=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//hudson.tasks.LogRotator/daysToKeep" 2>/dev/null || echo "-1")
    NUM_TO_KEEP=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//hudson.tasks.LogRotator/numToKeep" 2>/dev/null || echo "-1")
    ARTIFACT_DAYS=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//hudson.tasks.LogRotator/artifactDaysToKeep" 2>/dev/null || echo "-1")
    ARTIFACT_NUM=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//hudson.tasks.LogRotator/artifactNumToKeep" 2>/dev/null || echo "-1")
    
    # If field is empty in XML, it's effectively -1
    [ -z "$DAYS_TO_KEEP" ] && DAYS_TO_KEEP="-1"
    [ -z "$NUM_TO_KEEP" ] && NUM_TO_KEEP="-1"
    [ -z "$ARTIFACT_DAYS" ] && ARTIFACT_DAYS="-1"
    [ -z "$ARTIFACT_NUM" ] && ARTIFACT_NUM="-1"
    
    # Get current Hash
    CURRENT_HASH=$(echo "$CONFIG_XML" | md5sum | awk '{print $1}')
    INITIAL_HASH=$(cat "/tmp/task_initial_state/${JOB_NAME}_hash.txt" 2>/dev/null || echo "")
    
    # Check if config changed
    CONFIG_CHANGED="false"
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        CONFIG_CHANGED="true"
    fi
    
    # Get current build count (to ensure builds weren't manually deleted)
    BUILD_COUNT=$(jenkins_api "job/$JOB_NAME/api/json" | jq '.builds | length')
    
    # Construct JSON object for this job
    JOB_JSON=$(jq -n \
        --arg name "$JOB_NAME" \
        --arg has_rotator "$HAS_ROTATOR" \
        --arg days "$DAYS_TO_KEEP" \
        --arg num "$NUM_TO_KEEP" \
        --arg a_days "$ARTIFACT_DAYS" \
        --arg a_num "$ARTIFACT_NUM" \
        --arg changed "$CONFIG_CHANGED" \
        --argjson builds "$BUILD_COUNT" \
        '{
            name: $name,
            has_rotator: $has_rotator,
            daysToKeep: $days,
            numToKeep: $num,
            artifactDaysToKeep: $a_days,
            artifactNumToKeep: $a_num,
            config_changed: $changed,
            build_count: $builds
        }')
    
    if [ -z "$JSON_PARTS" ]; then
        JSON_PARTS="$JOB_JSON"
    else
        JSON_PARTS="$JSON_PARTS, $JOB_JSON"
    fi
done

# Assemble final JSON
echo "[$JSON_PARTS]" > /tmp/temp_result.json

# Wrap in main object with timestamp
jq -n \
    --slurpfile jobs /tmp/temp_result.json \
    --arg timestamp "$(date -Iseconds)" \
    '{
        jobs: $jobs[0],
        export_timestamp: $timestamp
    }' > /tmp/configure_log_rotation_result.json

rm -f /tmp/temp_result.json

echo "Result JSON saved:"
cat /tmp/configure_log_rotation_result.json
echo ""
echo "=== Export Complete ==="