#!/bin/bash
echo "=== Exporting wfs_t_update_feature result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Query PostGIS for the target city's current population
# Target: Shanghai
TARGET_CITY="Shanghai"
TARGET_VAL="28543210"

CURRENT_VAL=$(postgis_query "SELECT pop_max FROM ne_populated_places WHERE name = '$TARGET_CITY';")
echo "Current $TARGET_CITY population: $CURRENT_VAL"

# 2. Check for global side effects (how many rows have this specific value?)
# We expect exactly 1 if the filter was correct. If 0, update failed. If >1, filter was too broad.
MATCH_COUNT=$(postgis_query "SELECT count(*) FROM ne_populated_places WHERE pop_max = $TARGET_VAL;")
echo "Rows with target value: $MATCH_COUNT"

# 3. Check artifacts
REQ_PATH="/home/ga/wfs_update.xml"
RESP_PATH="/home/ga/wfs_response.xml"

REQ_EXISTS="false"
REQ_CONTENT=""
if [ -f "$REQ_PATH" ]; then
    REQ_EXISTS="true"
    # Read first 500 chars for verification context
    REQ_CONTENT=$(head -c 500 "$REQ_PATH" | base64 -w 0)
fi

RESP_EXISTS="false"
RESP_SUCCESS="false"
if [ -f "$RESP_PATH" ]; then
    RESP_EXISTS="true"
    if grep -q "TransactionResponse" "$RESP_PATH" && grep -q "totalUpdated=\"1\"" "$RESP_PATH"; then
        RESP_SUCCESS="true"
    # Handle WFS 2.0 or different versions where attribute might vary slightly
    elif grep -q "TransactionResponse" "$RESP_PATH" && grep -q "totalUpdated>1<" "$RESP_PATH"; then
        RESP_SUCCESS="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_city": "$TARGET_CITY",
    "current_population": $([ -n "$CURRENT_VAL" ] && echo "$CURRENT_VAL" || echo "0"),
    "target_population": $TARGET_VAL,
    "match_count": $([ -n "$MATCH_COUNT" ] && echo "$MATCH_COUNT" || echo "0"),
    "request_file_exists": $REQ_EXISTS,
    "request_content_b64": "$REQ_CONTENT",
    "response_file_exists": $RESP_EXISTS,
    "response_indicates_success": $RESP_SUCCESS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="