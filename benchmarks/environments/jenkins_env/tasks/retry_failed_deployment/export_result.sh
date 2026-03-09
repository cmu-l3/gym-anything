#!/bin/bash
# Export script for Retry Failed Deployment task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

JOB_NAME="Payment-Gateway-Deploy"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get info about the last build
echo "Fetching last build info..."
LAST_BUILD_JSON=$(jenkins_api "job/$JOB_NAME/lastBuild/api/json")

# Extract Build Number
LAST_BUILD_NUMBER=$(echo "$LAST_BUILD_JSON" | jq -r '.number')

# Extract Parameters
# Jenkins API stores parameters in actions -> parameters
PARAMS_JSON=$(echo "$LAST_BUILD_JSON" | jq -r '.actions[] | select(.parameters) | .parameters')

ACTUAL_TAG=$(echo "$PARAMS_JSON" | jq -r '.[] | select(.name=="ARTIFACT_TAG") | .value')
ACTUAL_REGION=$(echo "$PARAMS_JSON" | jq -r '.[] | select(.name=="REGION") | .value')
ACTUAL_RESTART=$(echo "$PARAMS_JSON" | jq -r '.[] | select(.name=="FORCE_RESTART") | .value')

# 2. Get Ground Truth
if [ -f /tmp/expected_params.json ]; then
    EXPECTED_TAG=$(jq -r '.expected_tag' /tmp/expected_params.json)
    EXPECTED_REGION=$(jq -r '.expected_region' /tmp/expected_params.json)
else
    EXPECTED_TAG="UNKNOWN"
    EXPECTED_REGION="UNKNOWN"
fi

echo "Last Build: #$LAST_BUILD_NUMBER"
echo "Params Found: Tag=$ACTUAL_TAG, Region=$ACTUAL_REGION, Restart=$ACTUAL_RESTART"

# 3. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "last_build_number": $LAST_BUILD_NUMBER,
    "actual_tag": "$ACTUAL_TAG",
    "actual_region": "$ACTUAL_REGION",
    "actual_restart": $ACTUAL_RESTART,
    "expected_tag": "$EXPECTED_TAG",
    "expected_region": "$EXPECTED_REGION",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json