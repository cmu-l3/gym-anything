#!/bin/bash
# Export script for Deprecate Jenkins Job task
# Checks if the job is disabled and description is updated

echo "=== Exporting Deprecate Job Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

JOB_NAME="Legacy-Ecommerce-Monolith"
JOB_EXISTS="false"
IS_DISABLED="false"
DESCRIPTION=""
BUILDABLE="true"
COLOR=""

echo "Checking status of job '$JOB_NAME'..."

if job_exists "$JOB_NAME"; then
    JOB_EXISTS="true"
    
    # Get API JSON
    API_JSON=$(jenkins_api "job/$JOB_NAME/api/json")
    
    # Extract fields
    COLOR=$(echo "$API_JSON" | jq -r '.color' 2>/dev/null)
    BUILDABLE=$(echo "$API_JSON" | jq -r '.buildable' 2>/dev/null)
    DESCRIPTION=$(echo "$API_JSON" | jq -r '.description // ""' 2>/dev/null)
    
    echo "Job Color: $COLOR"
    echo "Job Buildable: $BUILDABLE"
    echo "Job Description: $DESCRIPTION"
    
    # Check if disabled
    # In Jenkins API, 'buildable' is false when disabled
    # Also color might be 'disabled' or 'disabled_anime'
    if [ "$BUILDABLE" = "false" ]; then
        IS_DISABLED="true"
    fi
    
    # Double check via config.xml for <disabled> tag
    CONFIG_XML=$(get_job_config "$JOB_NAME")
    DISABLED_TAG=$(echo "$CONFIG_XML" | grep "<disabled>true</disabled>" || true)
    if [ -n "$DISABLED_TAG" ]; then
        echo "Confirmed disabled via config.xml"
        IS_DISABLED="true"
    fi
else
    echo "Job '$JOB_NAME' not found (may have been deleted)"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/deprecate_result.XXXXXX.json)
jq -n \
    --arg job_exists "$JOB_EXISTS" \
    --arg is_disabled "$IS_DISABLED" \
    --arg description "$DESCRIPTION" \
    --arg color "$COLOR" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        job_exists: ($job_exists == "true"),
        is_disabled: ($is_disabled == "true"),
        description: $description,
        color: $color,
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

# Move to safe location
rm -f /tmp/deprecate_job_result.json 2>/dev/null || sudo rm -f /tmp/deprecate_job_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/deprecate_job_result.json
chmod 666 /tmp/deprecate_job_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/deprecate_job_result.json
echo "=== Export Complete ==="