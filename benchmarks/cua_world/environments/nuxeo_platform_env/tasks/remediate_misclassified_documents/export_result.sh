#!/bin/bash
# Post-task export for remediate_misclassified_documents

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
echo "Capturing final state..."
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true

# 2. Gather Document Data via API
WS_PATH="/default-domain/workspaces/Incoming-Scans"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTROL_INITIAL_MOD=$(cat /tmp/control_doc_initial_mod.txt 2>/dev/null || echo "")

# Function to get doc properties safely
get_doc_props() {
    local name="$1"
    nuxeo_api GET "/path$WS_PATH/$name" | python3 -c "
import sys, json
try:
    doc = json.load(sys.stdin)
    props = doc.get('properties', {})
    res = {
        'uid': doc.get('uid'),
        'type': doc.get('type'),
        'nature': props.get('dc:nature'),
        'modified': props.get('dc:modified'),
        'lastContributor': props.get('dc:lastContributor')
    }
    print(json.dumps(res))
except Exception:
    print('{}')
"
}

echo "Fetching document states..."
DOC1_JSON=$(get_doc_props "Vendor-Contract-Alpha")
DOC2_JSON=$(get_doc_props "Service-Level-Agreement-2023")
DOC3_JSON=$(get_doc_props "Office-Supplies-Invoice-9921")

# 3. Check if Nuxeo/Firefox is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
  "task_start_ts": $TASK_START,
  "control_initial_mod": "$CONTROL_INITIAL_MOD",
  "app_running": $APP_RUNNING,
  "documents": {
    "Vendor-Contract-Alpha": $DOC1_JSON,
    "Service-Level-Agreement-2023": $DOC2_JSON,
    "Office-Supplies-Invoice-9921": $DOC3_JSON
  }
}
EOF

# 5. Set permissions for the verifier to read
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"