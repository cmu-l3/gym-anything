#!/bin/bash
echo "=== Exporting implement_isolated_workspace result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

EXPECTED_WS="alpha_corp"
EXPECTED_LAYER="secure_rivers"
EXPECTED_STORE="alpha_ds"

# 1. Check Workspace Configuration via REST API
# We need to verify 'isolated': true
WS_JSON=$(gs_rest_get "workspaces/${EXPECTED_WS}.json")
WS_EXISTS="false"
IS_ISOLATED="false"

if echo "$WS_JSON" | grep -q "\"name\":\"${EXPECTED_WS}\""; then
    WS_EXISTS="true"
    # Check isolation status
    # Note: JSON format might be {"workspace":{"name":"...","isolated":true,...}}
    IS_ISOLATED=$(echo "$WS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('workspace',{}).get('isolated', False)).lower())" 2>/dev/null || echo "false")
fi

# 2. Check Layer Configuration via REST API
LAYER_JSON=$(gs_rest_get "workspaces/${EXPECTED_WS}/layers/${EXPECTED_LAYER}.json")
LAYER_EXISTS="false"
LAYER_ENABLED="false"

if echo "$LAYER_JSON" | grep -q "\"name\":\"${EXPECTED_LAYER}\""; then
    LAYER_EXISTS="true"
    LAYER_ENABLED=$(echo "$LAYER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('layer',{}).get('enabled', False)).lower())" 2>/dev/null || echo "false")
fi

# 3. Verify Isolation Behavior (The Real Test)
# Fetch Global Capabilities
GLOBAL_CAPS=$(curl -s "http://localhost:8080/geoserver/wfs?request=GetCapabilities&version=1.1.0")
# Fetch Workspace Capabilities
VIRTUAL_CAPS=$(curl -s "http://localhost:8080/geoserver/${EXPECTED_WS}/wfs?request=GetCapabilities&version=1.1.0")

# Check visibility
# We look for the fully qualified name e.g. <Name>alpha_corp:secure_rivers</Name> or just the name in FeatureTypeList
VISIBLE_IN_GLOBAL="false"
VISIBLE_IN_VIRTUAL="false"

if echo "$GLOBAL_CAPS" | grep -q "${EXPECTED_WS}:${EXPECTED_LAYER}"; then
    VISIBLE_IN_GLOBAL="true"
fi

if echo "$VIRTUAL_CAPS" | grep -q "${EXPECTED_WS}:${EXPECTED_LAYER}"; then
    VISIBLE_IN_VIRTUAL="true"
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "workspace_exists": $WS_EXISTS,
    "is_isolated": $IS_ISOLATED,
    "layer_exists": $LAYER_EXISTS,
    "layer_enabled": $LAYER_ENABLED,
    "visible_in_global": $VISIBLE_IN_GLOBAL,
    "visible_in_virtual": $VISIBLE_IN_VIRTUAL,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/isolated_workspace_result.json"

echo "=== Export complete ==="