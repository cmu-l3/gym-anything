#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve Target and Distractor IDs saved during setup
TARGET_METHOD_ID=$(cat /tmp/target_method_id.txt 2>/dev/null || echo "")
DISTRACTOR_METHOD_ID=$(cat /tmp/distractor_method_id.txt 2>/dev/null || echo "")

# Fetch current COD settings from database
echo "Fetching COD settings..."
COD_SETTINGS_JSON=$(wp option get woocommerce_cod_settings --format=json --allow-root 2>/dev/null || echo "{}")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_method_id": "$TARGET_METHOD_ID",
    "distractor_method_id": "$DISTRACTOR_METHOD_ID",
    "cod_settings": $COD_SETTINGS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="