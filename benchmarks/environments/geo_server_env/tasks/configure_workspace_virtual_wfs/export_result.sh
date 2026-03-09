#!/bin/bash
echo "=== Exporting configure_workspace_virtual_wfs result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

# 1. Check Output Files
CAPS_FILE="/home/ga/ne_wfs_capabilities.xml"
FEAT_FILE="/home/ga/ne_countries_features.json"

CAPS_EXISTS="false"
CAPS_TITLE_FOUND="false"
if [ -f "$CAPS_FILE" ]; then
    CAPS_EXISTS="true"
    # Check if file was created during task
    CAPS_MTIME=$(stat -c %Y "$CAPS_FILE" 2>/dev/null || echo "0")
    if [ "$CAPS_MTIME" -ge "$TASK_START" ]; then
        # Check content for the specific title
        if grep -q "Natural Earth Feature Service" "$CAPS_FILE"; then
            CAPS_TITLE_FOUND="true"
        fi
    fi
fi

FEAT_EXISTS="false"
FEAT_COUNT=-1
if [ -f "$FEAT_FILE" ]; then
    FEAT_EXISTS="true"
    FEAT_MTIME=$(stat -c %Y "$FEAT_FILE" 2>/dev/null || echo "0")
    if [ "$FEAT_MTIME" -ge "$TASK_START" ]; then
        # Count features using Python to parse JSON
        FEAT_COUNT=$(python3 -c "
import sys, json
try:
    with open('$FEAT_FILE') as f:
        data = json.load(f)
        print(len(data.get('features', [])))
except:
    print('-1')
" 2>/dev/null || echo "-1")
    fi
fi

# 2. Check GeoServer Configuration via REST API
# We check if settings now exist at the workspace level
WFS_SETTINGS_STATUS=$(gs_rest_status "services/wfs/workspaces/ne/settings.json")
WFS_SETTINGS_JSON="{}"

if [ "$WFS_SETTINGS_STATUS" = "200" ]; then
    WFS_SETTINGS_JSON=$(gs_rest_get "services/wfs/workspaces/ne/settings.json")
fi

# Extract values
ACTUAL_TITLE=$(echo "$WFS_SETTINGS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('title',''))" 2>/dev/null || echo "")
ACTUAL_ABSTRACT=$(echo "$WFS_SETTINGS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('abstract',''))" 2>/dev/null || echo "")
ACTUAL_MAX_FEATURES=$(echo "$WFS_SETTINGS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('maxFeatures',''))" 2>/dev/null || echo "")
ACTUAL_ENABLED=$(echo "$WFS_SETTINGS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('wfs',{}).get('enabled','False')).lower())" 2>/dev/null || echo "false")
ACTUAL_SERVICE_LEVEL=$(echo "$WFS_SETTINGS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('serviceLevel',''))" 2>/dev/null || echo "")

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "wfs_settings_found": $([ "$WFS_SETTINGS_STATUS" = "200" ] && echo "true" || echo "false"),
    "actual_title": "$(json_escape "$ACTUAL_TITLE")",
    "actual_abstract": "$(json_escape "$ACTUAL_ABSTRACT")",
    "actual_max_features": "$(json_escape "$ACTUAL_MAX_FEATURES")",
    "actual_enabled": $ACTUAL_ENABLED,
    "actual_service_level": "$(json_escape "$ACTUAL_SERVICE_LEVEL")",
    "capabilities_file_exists": $CAPS_EXISTS,
    "capabilities_title_found": $CAPS_TITLE_FOUND,
    "features_file_exists": $FEAT_EXISTS,
    "features_count": $FEAT_COUNT,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_wms_result.json"

echo "=== Export complete ==="