#!/bin/bash
set -e

echo "=== Exporting Identify Approved Asset results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Load ground truth
if [ ! -f /tmp/ground_truth.json ]; then
    echo "ERROR: Ground truth file missing!"
    echo "{}" > /tmp/task_result.json
    exit 1
fi

CORRECT_UID=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth.json')).get('correct_uid', ''))")
WRONG_UID=$(python3 -c "import json; print(json.load(open('/tmp/ground_truth.json')).get('wrong_uid', ''))")

echo "Verifying Correct UID: $CORRECT_UID"
echo "Verifying Wrong UID: $WRONG_UID"

# Query Nuxeo API for the final state of both documents
# We use the UID to query, so even if they renamed it, we find the same object.

get_doc_title() {
    local uid="$1"
    nuxeo_api GET "/id/$uid" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties', {}).get('dc:title', ''))" 2>/dev/null || echo ""
}

# Get final titles
TITLE_CORRECT_DOC=$(get_doc_title "$CORRECT_UID")
TITLE_WRONG_DOC=$(get_doc_title "$WRONG_UID")

echo "Final Title (Correct Doc): '$TITLE_CORRECT_DOC'"
echo "Final Title (Wrong Doc):   '$TITLE_WRONG_DOC'"

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
# Use a temp file and move it to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat <<EOF > "$TEMP_JSON"
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "correct_uid": "$CORRECT_UID",
    "wrong_uid": "$WRONG_UID",
    "final_title_correct": "$TITLE_CORRECT_DOC",
    "final_title_wrong": "$TITLE_WRONG_DOC",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="