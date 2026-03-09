#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_expense_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch all relevant documents from CouchDB for the verifier to analyze
# We look for any document that looks like an expense or contains the relevant keywords
echo "Fetching candidate documents from CouchDB..."

CANDIDATE_DOCS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    candidates = []
    
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        doc_str = json.dumps(doc).lower()
        
        # Criteria for being a candidate document:
        # 1. Has 'expense' or 'social' in type/id AND has 'cost'/'amount'
        # 2. OR contains our specific keywords 'transportation' + '45'
        
        is_candidate = False
        
        if ('expense' in doc_str or 'social' in doc_str) and ('cost' in doc_str or 'amount' in doc_str):
            is_candidate = True
        
        if 'transportation' in doc_str and ('45' in doc_str or '45.00' in doc_str):
            is_candidate = True
            
        if is_candidate:
            candidates.append(doc)
            
    print(json.dumps(candidates))
except Exception as e:
    print('[]')
" 2>/dev/null || echo "[]")

# Check if Firefox is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_expense_count": $INITIAL_COUNT,
    "candidate_docs": $CANDIDATE_DOCS,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="