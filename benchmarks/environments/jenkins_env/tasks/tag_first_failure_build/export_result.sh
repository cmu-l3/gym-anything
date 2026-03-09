#!/bin/bash
echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JOB_NAME="Nightly-Quality-Gate"

# Get the target build ID recorded during setup
TARGET_BUILD_ID=$(cat /tmp/target_build_id.txt 2>/dev/null || echo "3")
PREV_ID=$((TARGET_BUILD_ID - 1))
NEXT_ID=$((TARGET_BUILD_ID + 1))

# Function to get description safely
get_build_desc() {
    local id="$1"
    # Using curl/jq directly to handle missing builds gracefully
    curl -s -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/job/$JOB_NAME/$id/api/json" | jq -r '.description // empty'
}

echo "Fetching descriptions..."
TARGET_DESC=$(get_build_desc "$TARGET_BUILD_ID")
PREV_DESC=$(get_build_desc "$PREV_ID")
NEXT_DESC=$(get_build_desc "$NEXT_ID")

echo "Target ($TARGET_BUILD_ID): $TARGET_DESC"
echo "Prev ($PREV_ID): $PREV_DESC"
echo "Next ($NEXT_ID): $NEXT_DESC"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_build_id": $TARGET_BUILD_ID,
    "target_description": "$(echo "$TARGET_DESC" | sed 's/"/\\"/g')",
    "prev_build_id": $PREV_ID,
    "prev_description": "$(echo "$PREV_DESC" | sed 's/"/\\"/g')",
    "next_build_id": $NEXT_ID,
    "next_description": "$(echo "$NEXT_DESC" | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="