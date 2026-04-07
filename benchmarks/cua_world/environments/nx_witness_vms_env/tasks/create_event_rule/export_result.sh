#!/bin/bash
echo "=== Exporting create_event_rule results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# 1. Fetch Final Rules State via API
# ============================================================
echo "Fetching final rules..."
FINAL_RULES_JSON=$(nx_api_get "/rest/v1/rules" 2>/dev/null || echo "[]")
echo "$FINAL_RULES_JSON" > /tmp/final_rules.json

# ============================================================
# 2. Capture Final Screenshot
# ============================================================
take_screenshot /tmp/task_final.png

# ============================================================
# 3. Prepare Result JSON
# ============================================================
# We structure the JSON so the verifier can easily parse it
# We'll embed the rules list directly or save it to a file the verifier reads?
# Better to embed the relevant data into the result json.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use Python to construct the detailed result object
python3 -c "
import json
import os
import time

try:
    with open('/tmp/initial_rules.json', 'r') as f:
        initial_rules = json.load(f)
except:
    initial_rules = []

try:
    with open('/tmp/final_rules.json', 'r') as f:
        final_rules = json.load(f)
except:
    final_rules = []

# Create a map of initial IDs
initial_ids = set(r.get('id') for r in initial_rules)

# Find new rules
new_rules = [r for r in final_rules if r.get('id') not in initial_ids]

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': len(initial_rules),
    'final_count': len(final_rules),
    'new_rules': new_rules,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="