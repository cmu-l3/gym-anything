#!/bin/bash
echo "=== Exporting add_concept_synonym result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CONCEPT_UUID="5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query the final state of the concept
echo "Querying OpenMRS API for concept state..."
CONCEPT_JSON=$(openmrs_api_get "/concept/${CONCEPT_UUID}?v=full")

# Save raw JSON for debugging/verification
echo "$CONCEPT_JSON" > /tmp/final_concept_state.json

# 2. Check if browser is running
BROWSER_RUNNING="false"
if pgrep -f epiphany > /dev/null; then
    BROWSER_RUNNING="true"
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "browser_running": $BROWSER_RUNNING,
    "concept_data": $CONCEPT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="