#!/bin/bash
# Export script for Register Build Agent task
# Exports the node configuration and existence status

echo "=== Exporting Register Build Agent Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TARGET_NODE="frontend-builder-01"
OUTPUT_FILE="/tmp/register_build_agent_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Get List of All Computers (to verify count increase)
ALL_COMPUTERS_JSON=$(jenkins_api "computer/api/json?depth=1" 2>/dev/null)
CURRENT_COUNT=$(echo "$ALL_COMPUTERS_JSON" | jq '.computer | length' 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_node_count 2>/dev/null || echo "0")

echo "Node count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# 2. Check if specific node exists
# We use the config.xml endpoint to get the raw configuration for verification
# and the api/json endpoint for runtime status
echo "Checking for node '$TARGET_NODE'..."

NODE_EXISTS="false"
NODE_CONFIG_XML=""
NODE_INFO_JSON="{}"

# Check existence via API status code
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$JENKINS_USER:$JENKINS_PASS" "$JENKINS_URL/computer/$TARGET_NODE/api/json")

if [ "$HTTP_CODE" = "200" ]; then
    NODE_EXISTS="true"
    echo "Node '$TARGET_NODE' found!"
    
    # Get Config XML
    NODE_CONFIG_XML=$(jenkins_api "computer/$TARGET_NODE/config.xml" 2>/dev/null)
    
    # Get Runtime Info
    NODE_INFO_JSON=$(jenkins_api "computer/$TARGET_NODE/api/json" 2>/dev/null)
else
    echo "Node '$TARGET_NODE' NOT found (HTTP $HTTP_CODE)"
fi

# 3. Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON using jq
# We encode the XML as a string to avoid JSON parsing issues with XML content
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --arg node_exists "$NODE_EXISTS" \
    --arg node_name "$TARGET_NODE" \
    --arg config_xml "$NODE_CONFIG_XML" \
    --argjson info_json "${NODE_INFO_JSON:-{}}" \
    --argjson initial_count "${INITIAL_COUNT:-0}" \
    --argjson current_count "${CURRENT_COUNT:-0}" \
    --argjson task_start "$TASK_START" \
    --argjson task_end "$TASK_END" \
    '{
        node_exists: ($node_exists == "true"),
        node_name: $node_name,
        config_xml: $config_xml,
        runtime_info: $info_json,
        initial_node_count: $initial_count,
        current_node_count: $current_count,
        task_start: $task_start,
        task_end: $task_end,
        screenshot_path: "/tmp/task_final.png"
    }' > "$TEMP_JSON"

# Move temp file to final location
rm -f "$OUTPUT_FILE" 2>/dev/null || sudo rm -f "$OUTPUT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$OUTPUT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$OUTPUT_FILE"
chmod 666 "$OUTPUT_FILE" 2>/dev/null || sudo chmod 666 "$OUTPUT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to $OUTPUT_FILE"
echo "=== Export Complete ==="