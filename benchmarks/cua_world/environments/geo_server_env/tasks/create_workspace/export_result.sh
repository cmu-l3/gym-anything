#!/bin/bash
echo "=== Exporting create_workspace result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_COUNT=$(cat /tmp/initial_workspace_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_workspace_count)

# Check for the expected workspace via REST API
EXPECTED_NAME="natural_earth"
WORKSPACE_FOUND="false"
WORKSPACE_NAME=""
NAMESPACE_URI=""

# Try exact match first
WS_STATUS=$(gs_rest_status "workspaces/${EXPECTED_NAME}.json")
if [ "$WS_STATUS" = "200" ]; then
    WS_DATA=$(gs_rest_get "workspaces/${EXPECTED_NAME}.json")
    WORKSPACE_FOUND="true"
    WORKSPACE_NAME=$(echo "$WS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('workspace',{}).get('name',''))" 2>/dev/null || echo "")
    NAMESPACE_URI=$(gs_rest_get "namespaces/${EXPECTED_NAME}.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('namespace',{}).get('uri',''))" 2>/dev/null || echo "")
fi

# If exact match fails, search all workspaces for partial match
if [ "$WORKSPACE_FOUND" = "false" ]; then
    ALL_WS=$(gs_rest_get "workspaces.json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ws = d.get('workspaces', {}).get('workspace', [])
if not isinstance(ws, list):
    ws = [ws] if ws else []
for w in ws:
    print(w['name'])
" 2>/dev/null)

    for ws_name in $ALL_WS; do
        ws_lower=$(echo "$ws_name" | tr '[:upper:]' '[:lower:]')
        if echo "$ws_lower" | grep -q "natural.*earth\|earth.*natural\|natearth\|nat_earth"; then
            WORKSPACE_FOUND="true"
            WORKSPACE_NAME="$ws_name"
            NAMESPACE_URI=$(gs_rest_get "namespaces/${ws_name}.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('namespace',{}).get('uri',''))" 2>/dev/null || echo "")
            break
        fi
    done
fi

# If still not found, check if any new workspace was created (only if count increased by 1-2)
if [ "$WORKSPACE_FOUND" = "false" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ] && [ "$((CURRENT_COUNT - INITIAL_COUNT))" -le 2 ]; then
    # Get the newest workspace (last in list)
    NEWEST_WS=$(gs_rest_get "workspaces.json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ws = d.get('workspaces', {}).get('workspace', [])
if not isinstance(ws, list):
    ws = [ws] if ws else []
if ws:
    print(ws[-1]['name'])
" 2>/dev/null)
    if [ -n "$NEWEST_WS" ]; then
        WORKSPACE_FOUND="true"
        WORKSPACE_NAME="$NEWEST_WS"
        NAMESPACE_URI=$(gs_rest_get "namespaces/${NEWEST_WS}.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('namespace',{}).get('uri',''))" 2>/dev/null || echo "")
    fi
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_workspace_count": ${INITIAL_COUNT},
    "current_workspace_count": ${CURRENT_COUNT},
    "workspace_found": ${WORKSPACE_FOUND},
    "workspace_name": "$(json_escape "$WORKSPACE_NAME")",
    "namespace_uri": "$(json_escape "$NAMESPACE_URI")",
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_workspace_result.json"

echo "=== Export complete ==="
