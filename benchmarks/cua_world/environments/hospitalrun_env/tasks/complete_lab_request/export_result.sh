#!/bin/bash
echo "=== Exporting complete_lab_request result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
LAB_ID="lab_p1_task_cbc"
INITIAL_REV=$(cat /tmp/initial_lab_rev.txt 2>/dev/null || echo "")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query the Lab Document
echo "Fetching final lab document state..."
LAB_DOC_JSON=$(hr_couch_get "$LAB_ID")

# 4. Extract Key Fields using Python for reliability
# We extract status, result text, notes, and the current revision
PYTHON_SCRIPT=$(cat <<EOF
import sys, json, time

try:
    doc = json.load(sys.stdin)
    data = doc.get('data', doc)
    
    current_rev = doc.get('_rev', '')
    initial_rev = "$INITIAL_REV"
    
    # Check modification
    is_modified = (current_rev != initial_rev) and (initial_rev != "")
    
    # Extract fields
    status = data.get('status', '').lower()
    result_text = data.get('result', '')
    notes = data.get('notes', '')
    
    output = {
        "exists": True,
        "status": status,
        "result_text": result_text,
        "notes": notes,
        "is_modified": is_modified,
        "initial_rev": initial_rev,
        "final_rev": current_rev,
        "timestamp": time.time()
    }
except Exception as e:
    output = {
        "exists": False,
        "error": str(e)
    }

print(json.dumps(output))
EOF
)

# Generate JSON result
echo "$LAB_DOC_JSON" | python3 -c "$PYTHON_SCRIPT" > /tmp/parsed_result.json

# 5. Create final export structure
cat > /tmp/task_result.json <<EOF
{
    "lab_data": $(cat /tmp/parsed_result.json),
    "task_start": $TASK_START_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json