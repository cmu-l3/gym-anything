#!/bin/bash
echo "=== Exporting add_pricing_item results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Get Initial Count
INITIAL_COUNT=$(cat /tmp/initial_pricing_count.txt 2>/dev/null || echo "0")

# 4. Query CouchDB for current state
echo "Querying CouchDB for pricing items..."
# Fetch all docs to process in Python for robust finding
ALL_DOCS_FILE="/tmp/all_docs.json"
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > "$ALL_DOCS_FILE"

# Extract relevant data using Python
# We look for:
# 1. Current total count of pricing items
# 2. The specific item created (by name)
# 3. Its fields (price, category, etc.)
python3 -c "
import sys, json, os

try:
    with open('$ALL_DOCS_FILE', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(0)

pricing_items = []
target_item = None

target_name = 'Portable Ultrasound - Limited Bedside'

for row in data.get('rows', []):
    doc = row.get('doc', {})
    # HospitalRun data is often nested in 'data' property, but sometimes flat
    d = doc.get('data', doc)
    
    # Check if it looks like a pricing item
    # Criteria: type='pricing' OR has 'price' and 'name' fields
    is_pricing = False
    if d.get('type') == 'pricing':
        is_pricing = True
    elif 'price' in d and 'name' in d:
        # Fallback heuristic
        is_pricing = True
        
    if is_pricing:
        pricing_items.append(d)
        if d.get('name') == target_name:
            target_item = d

result = {
    'initial_count': int(os.environ.get('INITIAL_COUNT', 0)),
    'final_count': len(pricing_items),
    'target_found': target_item is not None,
    'target_item': target_item,
    'task_start': int(os.environ.get('TASK_START', 0)),
    'task_end': int(os.environ.get('TASK_END', 0))
}

print(json.dumps(result))
" > /tmp/db_analysis.json

# 5. Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 6. Create final result JSON
# Merge the python analysis with bash-collected info
jq -n \
    --slurpfile db /tmp/db_analysis.json \
    --arg app_running "$APP_RUNNING" \
    --arg screenshot "/tmp/task_final.png" \
    '{
        db_result: $db[0],
        app_was_running: ($app_running == "true"),
        screenshot_path: $screenshot
    }' > /tmp/task_result.json

# Cleanup
rm -f "$ALL_DOCS_FILE" /tmp/db_analysis.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="