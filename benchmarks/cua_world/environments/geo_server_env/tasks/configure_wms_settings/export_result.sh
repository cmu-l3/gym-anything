#!/bin/bash
echo "=== Exporting configure_wms_settings result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_MAX_MEMORY=$(cat /tmp/initial_max_memory 2>/dev/null || echo "unknown")
INITIAL_MAX_TIME=$(cat /tmp/initial_max_time 2>/dev/null || echo "unknown")
INITIAL_WATERMARK=$(cat /tmp/initial_watermark 2>/dev/null || echo "unknown")

# Get current WMS settings via REST API
WMS_DATA=$(gs_rest_get "services/wms/settings.json")

CURRENT_MAX_MEMORY=$(echo "$WMS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wms',{}).get('maxRequestMemory',''))" 2>/dev/null || echo "")
CURRENT_MAX_TIME=$(echo "$WMS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wms',{}).get('maxRenderingTime',''))" 2>/dev/null || echo "")
CURRENT_WATERMARK=$(echo "$WMS_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); wm=d.get('wms',{}).get('watermark',{}); print(str(wm.get('enabled', False)).lower())" 2>/dev/null || echo "false")

# Determine if settings changed
MEMORY_CHANGED="false"
TIME_CHANGED="false"
WATERMARK_CHANGED="false"

if [ "$CURRENT_MAX_MEMORY" != "$INITIAL_MAX_MEMORY" ] && [ -n "$CURRENT_MAX_MEMORY" ]; then
    MEMORY_CHANGED="true"
fi
if [ "$CURRENT_MAX_TIME" != "$INITIAL_MAX_TIME" ] && [ -n "$CURRENT_MAX_TIME" ]; then
    TIME_CHANGED="true"
fi
if [ "$CURRENT_WATERMARK" != "$INITIAL_WATERMARK" ]; then
    WATERMARK_CHANGED="true"
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_max_memory": "$(json_escape "$INITIAL_MAX_MEMORY")",
    "current_max_memory": "$(json_escape "$CURRENT_MAX_MEMORY")",
    "memory_changed": ${MEMORY_CHANGED},
    "initial_max_time": "$(json_escape "$INITIAL_MAX_TIME")",
    "current_max_time": "$(json_escape "$CURRENT_MAX_TIME")",
    "time_changed": ${TIME_CHANGED},
    "initial_watermark": "$(json_escape "$INITIAL_WATERMARK")",
    "current_watermark": "$(json_escape "$CURRENT_WATERMARK")",
    "watermark_changed": ${WATERMARK_CHANGED},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_wms_settings_result.json"

echo "=== Export complete ==="
