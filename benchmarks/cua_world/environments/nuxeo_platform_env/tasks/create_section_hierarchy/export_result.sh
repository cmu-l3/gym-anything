#!/bin/bash
# Export script for create_section_hierarchy task
# Queries Nuxeo API and saves state to JSON for the verifier

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_section_count.txt 2>/dev/null || echo "0")

# 3. Helper function to get document details safely
get_doc_details() {
    local path="$1"
    # Returns JSON object or null
    nuxeo_api GET "/path$path" 2>/dev/null
}

# 4. Gather Data
echo "Querying Nuxeo for section hierarchy..."

# Parent Section
PARENT_JSON=$(get_doc_details "/default-domain/sections/Department-Publications")

# Child Sections
ENG_JSON=$(get_doc_details "/default-domain/sections/Department-Publications/Engineering")
MKT_JSON=$(get_doc_details "/default-domain/sections/Department-Publications/Marketing")
LEGAL_JSON=$(get_doc_details "/default-domain/sections/Department-Publications/Legal")

# Current count of sections
FINAL_COUNT=$(nuxeo_api GET "/path/default-domain/sections/@children" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('resultsCount', 0))" 2>/dev/null || echo "0")

# Check if application (Firefox) is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 5. Construct Result JSON using Python for safety
# We embed the raw JSON responses from Nuxeo into the result so the verifier can parse them.
python3 -c "
import json
import sys
import time

def safe_load(json_str):
    try:
        if not json_str or json_str.strip() == '': return None
        return json.loads(json_str)
    except:
        return None

try:
    parent = safe_load('''$PARENT_JSON''')
    eng = safe_load('''$ENG_JSON''')
    mkt = safe_load('''$MKT_JSON''')
    legal = safe_load('''$LEGAL_JSON''')
except:
    parent = None; eng = None; mkt = None; legal = None

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'final_count': int('$FINAL_COUNT'),
    'app_running': '$APP_RUNNING' == 'true',
    'parent': parent,
    'children': {
        'Engineering': eng,
        'Marketing': mkt,
        'Legal': legal
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 6. Set permissions so the host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="