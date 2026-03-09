#!/bin/bash
echo "=== Exporting Task Results ==="

# Define IDs (must match setup_task.sh)
TARGET_REQ_ID="lab_p1_REQ001"
CONTROL_REQ_ID="lab_p1_REQ002"
TARGET_PATIENT_ID="patient_p1_P00555"
COUCH_URL="http://couchadmin:test@localhost:5984/main"

# Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to fetch doc status safely
get_doc_status() {
    local doc_id=$1
    # Check if doc exists
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "${COUCH_URL}/${doc_id}")
    
    if [ "$http_code" == "404" ]; then
        echo '{"exists": false, "deleted": true}'
    else
        # Fetch doc and extract relevant fields
        curl -s "${COUCH_URL}/${doc_id}" | python3 -c "
import sys, json
try:
    doc = json.load(sys.stdin)
    data = doc.get('data', {})
    res = {
        'exists': True,
        'deleted': doc.get('_deleted', False),
        'status': data.get('status', 'Unknown'),
        'labType': data.get('labType', ''),
        'patientId': data.get('patientId', '')
    }
    print(json.dumps(res))
except Exception:
    print('{\"error\": \"parse_error\"}')
"
    fi
}

# 1. Check Target Request (Should be deleted or Cancelled)
echo "Checking target request..."
TARGET_STATUS=$(get_doc_status "$TARGET_REQ_ID")

# 2. Check Control Request (Should exist and be Requested)
echo "Checking control request..."
CONTROL_STATUS=$(get_doc_status "$CONTROL_REQ_ID")

# 3. Check Patient Record (Should exist - anti-gaming check)
echo "Checking patient record..."
PATIENT_STATUS=$(get_doc_status "$TARGET_PATIENT_ID")

# 4. Check timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_request": $TARGET_STATUS,
    "control_request": $CONTROL_STATUS,
    "patient_record": $PATIENT_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with read permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json