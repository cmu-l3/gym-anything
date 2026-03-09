#!/bin/bash
echo "=== Exporting disable_virtual_server task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TARGET_DOMAIN="greenfield-consulting.test"
DOMAIN_HOME=$(cat /tmp/initial_domain_home.txt 2>/dev/null || echo "/home/greenfield-consulting")

# ---------------------------------------------------------------
# 1. Check Domain Existence & Status
# ---------------------------------------------------------------
DOMAIN_EXISTS="false"
IS_DISABLED="false"
DISABLE_REASON=""

if virtualmin_domain_exists "$TARGET_DOMAIN"; then
    DOMAIN_EXISTS="true"
    
    # Get multiline info
    DOMAIN_INFO=$(virtualmin list-domains --domain "$TARGET_DOMAIN" --multiline 2>/dev/null)
    
    # Check disabled status
    # Output typically looks like "Disabled?: Yes" or "Disabled?: No"
    if echo "$DOMAIN_INFO" | grep -i "Disabled" | grep -qi "Yes"; then
        IS_DISABLED="true"
    fi
    
    # Extract disable reason from config if possible
    # (Virtualmin stores this in the domain config file)
    DOMAIN_ID=$(get_domain_id "$TARGET_DOMAIN")
    if [ -n "$DOMAIN_ID" ] && [ -f "/etc/webmin/virtual-server/domains/${DOMAIN_ID}" ]; then
        DISABLE_REASON=$(grep "^disabled_reason=" "/etc/webmin/virtual-server/domains/${DOMAIN_ID}" | cut -d= -f2- || true)
        
        # Also check just 'reason' or other keys just in case
        if [ -z "$DISABLE_REASON" ]; then
             DISABLE_REASON=$(grep "^reason=" "/etc/webmin/virtual-server/domains/${DOMAIN_ID}" | cut -d= -f2- || true)
        fi
    fi
fi

# ---------------------------------------------------------------
# 2. Check Web Service Status
# ---------------------------------------------------------------
WEB_STATUS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    "http://localhost:80/" -H "Host: $TARGET_DOMAIN" 2>/dev/null || echo "000")

WEB_CONTENT_MARKER_FOUND="false"
CONTENT_SAMPLE=$(curl -sk "http://localhost:80/" -H "Host: $TARGET_DOMAIN" 2>/dev/null | head -20)
if echo "$CONTENT_SAMPLE" | grep -q "MARKER: ACTIVE_CONTENT_4781"; then
    WEB_CONTENT_MARKER_FOUND="true"
fi

# ---------------------------------------------------------------
# 3. Check Data Preservation
# ---------------------------------------------------------------
HOME_DIR_EXISTS="false"
if [ -d "$DOMAIN_HOME" ]; then
    HOME_DIR_EXISTS="true"
fi

# ---------------------------------------------------------------
# 4. Take Screenshot
# ---------------------------------------------------------------
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# ---------------------------------------------------------------
# 5. Export JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "domain_exists": $DOMAIN_EXISTS,
    "is_disabled": $IS_DISABLED,
    "disable_reason": "$(json_escape "$DISABLE_REASON")",
    "web_status_code": "$WEB_STATUS_CODE",
    "web_content_marker_found": $WEB_CONTENT_MARKER_FOUND,
    "home_dir_exists": $HOME_DIR_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="