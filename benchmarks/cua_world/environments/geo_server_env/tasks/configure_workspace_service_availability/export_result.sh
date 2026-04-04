#!/bin/bash
echo "=== Exporting configure_workspace_service_availability result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# Functional Testing of OGC Services
# ==============================================================================

# Helper to check service availability
# Returns "200" if accessible (Capabilities XML), "403/404" if blocked, or "DISABLED" if ServiceException found
check_service_status() {
    local service="$1"
    local url="${GS_URL}/ne/${service}?service=$(echo $service | tr '[:lower:]' '[:upper:]')&request=GetCapabilities"
    
    # Capture both HTTP code and content
    local output_file="/tmp/${service}_cap.xml"
    local http_code=$(curl -s -o "$output_file" -w "%{http_code}" "$url")
    
    if [ "$http_code" = "200" ]; then
        # Check if it's actually an exception report disguised as 200 (common in some OGC versions)
        if grep -qi "ServiceException" "$output_file" && grep -qi "disabled" "$output_file"; then
            echo "DISABLED"
        else
            echo "ACCESSIBLE"
        fi
    elif [ "$http_code" = "403" ] || [ "$http_code" = "404" ]; then
        echo "DISABLED"
    else
        echo "ERROR_${http_code}"
    fi
}

echo "Checking WFS..."
WFS_STATUS=$(check_service_status "wfs")
echo "WFS Status: $WFS_STATUS"

echo "Checking WCS..."
WCS_STATUS=$(check_service_status "wcs")
echo "WCS Status: $WCS_STATUS"

echo "Checking WMS..."
WMS_STATUS=$(check_service_status "wms")
echo "WMS Status: $WMS_STATUS"

# ==============================================================================
# Check WMS Title
# ==============================================================================
WMS_TITLE_FOUND="false"
ACTUAL_WMS_TITLE=""

if [ "$WMS_STATUS" = "ACCESSIBLE" ]; then
    # Parse Title from Capabilities XML
    # Look for first Service > Title
    ACTUAL_WMS_TITLE=$(cat /tmp/wms_cap.xml | python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    # Namespace handling is annoying in OGC, try naive search first
    # WMS 1.1.1 doesn't use namespaces heavily for top elements, 1.3.0 does
    # Simple strategy: iterate elements
    found_title = ''
    for elem in root.iter():
        if 'Service' in elem.tag:
            for child in elem:
                if 'Title' in child.tag:
                    found_title = child.text
                    break
        if found_title: break
    print(found_title or '')
except Exception as e:
    print('')
")
    
    EXPECTED="Natural Earth Visualization Service"
    if [ "$ACTUAL_WMS_TITLE" = "$EXPECTED" ]; then
        WMS_TITLE_FOUND="true"
    fi
fi

# ==============================================================================
# REST API Configuration Check (Backup)
# ==============================================================================
# Check if settings exist for the workspace
WFS_SETTINGS_EXIST=$(gs_rest_status "services/wfs/workspaces/ne/settings")
WMS_SETTINGS_EXIST=$(gs_rest_status "services/wms/workspaces/ne/settings")
WCS_SETTINGS_EXIST=$(gs_rest_status "services/wcs/workspaces/ne/settings")

# Check GUI interaction
GUI_INTERACTION=$(check_gui_interaction)

# ==============================================================================
# Create Result JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "wfs_status": "$WFS_STATUS",
    "wcs_status": "$WCS_STATUS",
    "wms_status": "$WMS_STATUS",
    "wms_title_found": $WMS_TITLE_FOUND,
    "actual_wms_title": "$(json_escape "$ACTUAL_WMS_TITLE")",
    "wfs_settings_exist": $([ "$WFS_SETTINGS_EXIST" = "200" ] && echo "true" || echo "false"),
    "wms_settings_exist": $([ "$WMS_SETTINGS_EXIST" = "200" ] && echo "true" || echo "false"),
    "wcs_settings_exist": $([ "$WCS_SETTINGS_EXIST" = "200" ] && echo "true" || echo "false"),
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_workspace_service_availability_result.json"

echo "=== Export complete ==="