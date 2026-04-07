#!/bin/bash
echo "=== Exporting enforce_bookmark_retention_policy result ==="

source /workspace/scripts/task_utils.sh

# Record final state
date +%s > /tmp/task_end_time.txt

# 1. Get current bookmarks from API to verify what remains
refresh_nx_token > /dev/null 2>&1 || true
TOKEN=$(get_nx_token)

echo "Fetching final bookmark list..."
curl -sk "${NX_BASE}/rest/v1/bookmarks" \
    -H "Authorization: Bearer ${TOKEN}" \
    --max-time 15 > /tmp/final_bookmarks.json

# 2. Check for agent's log file
LOG_FILE="/home/ga/Documents/retention_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    # Read first 500 bytes to avoid huge dumps
    LOG_CONTENT=$(head -c 500 "$LOG_FILE")
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare result JSON
# We include the ground truth created during setup for the verifier
GROUND_TRUTH="{}"
if [ -f "/tmp/bookmark_ground_truth.json" ]; then
    GROUND_TRUTH=$(cat /tmp/bookmark_ground_truth.json)
fi

FINAL_BOOKMARKS="[]"
if [ -f "/tmp/final_bookmarks.json" ]; then
    # Ensure it's valid JSON
    if jq empty /tmp/final_bookmarks.json 2>/dev/null; then
        FINAL_BOOKMARKS=$(cat /tmp/final_bookmarks.json)
    fi
fi

# Construct result object
python3 -c "
import json
import os

try:
    with open('/tmp/final_bookmarks.json', 'r') as f:
        final_b = json.load(f)
except:
    final_b = []

try:
    with open('/tmp/bookmark_ground_truth.json', 'r') as f:
        ground_truth = json.load(f)
except:
    ground_truth = []

result = {
    'final_bookmarks': final_b,
    'ground_truth': ground_truth,
    'log_file_exists': '${LOG_EXISTS}' == 'true',
    'log_content': '''${LOG_CONTENT}''',
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions so verifier can copy it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"