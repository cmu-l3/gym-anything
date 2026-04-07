#!/bin/bash
# Export script for grant_temporary_permissions
# Gathers Nuxeo ACL data and system state for verification

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Fetch Workspace Data with ACLs via REST API
# We need the 'acls' enricher to see permissions
echo "Fetching workspace ACLs..."
ACL_JSON_PATH="/tmp/workspace_acls.json"

# Note: We must use the correct credentials (Administrator)
# We fetch the specific workspace document with the 'acls' enricher
curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    -H "X-NXproperties: *" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/VendorContracts?enrichers.document=acls" \
    > "$ACL_JSON_PATH"

# 3. Check if 'contractor_sam' is present in the output (quick debug check)
if grep -q "contractor_sam" "$ACL_JSON_PATH"; then
    echo "Found 'contractor_sam' in ACL export."
    USER_FOUND="true"
else
    echo "User 'contractor_sam' NOT found in ACL export."
    USER_FOUND="false"
fi

# 4. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create consolidated JSON result
# We embed the entire ACL JSON content into the result file so the python verifier can parse it
# We use jq to safely construct the JSON if available, otherwise manual construction
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Safe way to embed the ACL JSON using python to avoid escaping issues
python3 -c "
import json
import os
import time

try:
    with open('$ACL_JSON_PATH', 'r') as f:
        acl_data = json.load(f)
except Exception:
    acl_data = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'user_found_in_export': $USER_FOUND,
    'workspace_data': acl_data,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# 6. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"