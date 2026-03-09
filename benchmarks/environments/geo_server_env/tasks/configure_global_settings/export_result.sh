#!/bin/bash
echo "=== Exporting configure_global_settings result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# 1. Fetch Current GeoServer Configuration via REST API
# ==============================================================================
SETTINGS_JSON=$(gs_rest_get "settings.json")
LOGGING_JSON=$(gs_rest_get "logging.json")
CONTACT_JSON=$(gs_rest_get "settings/contact.json")

# ==============================================================================
# 2. Check WMS GetCapabilities for Proxy Base URL
# ==============================================================================
CAPABILITIES_URL="http://localhost:8080/geoserver/wms?service=WMS&version=1.3.0&request=GetCapabilities"
CAPABILITIES_XML=$(curl -s "$CAPABILITIES_URL")

# Check if the proxy URL is present in the XML
PROXY_URL="https://maps.cityplanning.example.com/geoserver"
if echo "$CAPABILITIES_XML" | grep -q "$PROXY_URL"; then
    CAPABILITIES_HAS_PROXY="true"
else
    CAPABILITIES_HAS_PROXY="false"
fi

# ==============================================================================
# 3. Check Report File
# ==============================================================================
REPORT_PATH="/home/ga/global_settings_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT_BASE64=""
REPORT_MTIME=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Encode content to base64 to avoid JSON escaping issues
    REPORT_CONTENT_BASE64=$(cat "$REPORT_PATH" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ==============================================================================
# 4. Detect GUI Interaction via Access Logs
# ==============================================================================
GUI_INTERACTION="false"
ACCESS_LOG=$(cat /tmp/access_log_path 2>/dev/null || echo "")
START_COUNT=$(cat /tmp/access_log_start_count 2>/dev/null || echo "0")

if [ -n "$ACCESS_LOG" ]; then
    CURRENT_COUNT=$(docker exec gs-app wc -l < "$ACCESS_LOG" 2>/dev/null || echo "0")
    NEW_LINES=$((CURRENT_COUNT - START_COUNT))
    
    if [ "$NEW_LINES" -gt 0 ]; then
        # Check new lines for POST requests to Wicket pages (UI interaction)
        # Exclude REST API calls (/rest/)
        LOG_ACTIVITY=$(docker exec gs-app tail -n "$NEW_LINES" "$ACCESS_LOG" 2>/dev/null)
        
        # Look for POST requests that are NOT /rest/ and ARE part of the web admin (/geoserver/web/)
        if echo "$LOG_ACTIVITY" | grep "POST" | grep "/geoserver/web/" | grep -v "/rest/" > /dev/null; then
            GUI_INTERACTION="true"
        fi
    fi
fi

# ==============================================================================
# 5. Export to JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "settings": $SETTINGS_JSON,
    "logging": $LOGGING_JSON,
    "contact": $CONTACT_JSON,
    "capabilities_has_proxy": $CAPABILITIES_HAS_PROXY,
    "report": {
        "exists": $REPORT_EXISTS,
        "content_base64": "$REPORT_CONTENT_BASE64",
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "gui_interaction_detected": $GUI_INTERACTION,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_global_settings_result.json"

echo "=== Export complete ==="