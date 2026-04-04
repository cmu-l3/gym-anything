#!/bin/bash
echo "=== Exporting restore_virtual_server result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

DOMAIN="greenleaf-organics.test"
EXPECTED_MARKER=$(cat /tmp/expected_marker.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Domain Existence
DOMAIN_EXISTS="false"
if virtualmin_domain_exists "$DOMAIN"; then
    DOMAIN_EXISTS="true"
fi

# 2. Check Creation Timestamp (Anti-Gaming)
# We check the creation time of the domain config file or home dir
CREATED_DURING_TASK="false"
DOMAIN_CONFIG="/etc/webmin/virtual-server/domains"
if [ "$DOMAIN_EXISTS" = "true" ]; then
    # Get the ID to find the config file, or check home dir creation time
    HOME_DIR="/home/greenleaf-organics"
    if [ -d "$HOME_DIR" ]; then
        DIR_CTIME=$(stat -c %Y "$HOME_DIR")
        if [ "$DIR_CTIME" -ge "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
    fi
fi

# 3. Check Features
FEATURE_WEB="false"
FEATURE_DNS="false"
FEATURE_MAIL="false"
FEATURE_MYSQL="false"

if [ "$DOMAIN_EXISTS" = "true" ]; then
    FEATURES=$(virtualmin list-domains --domain "$DOMAIN" --multiline)
    
    if echo "$FEATURES" | grep -q "HTML directory"; then FEATURE_WEB="true"; fi
    if echo "$FEATURES" | grep -q "DNS zone"; then FEATURE_DNS="true"; fi
    if echo "$FEATURES" | grep -q "Mailboxes"; then FEATURE_MAIL="true"; fi
    if echo "$FEATURES" | grep -q "MySQL database"; then FEATURE_MYSQL="true"; fi
fi

# 4. Check Data Restoration (Marker File)
MARKER_RESTORED="false"
ACTUAL_MARKER=""
MARKER_PATH="/home/greenleaf-organics/public_html/restore_proof.txt"

if [ -f "$MARKER_PATH" ]; then
    ACTUAL_MARKER=$(cat "$MARKER_PATH")
    if [ "$ACTUAL_MARKER" = "$EXPECTED_MARKER" ]; then
        MARKER_RESTORED="true"
    fi
fi

# 5. Check Specific User Restoration
USER_RESTORED="false"
if virtualmin list-users --domain "$DOMAIN" 2>/dev/null | grep -q "info@$DOMAIN"; then
    USER_RESTORED="true"
fi

# 6. Check Web Response
WEB_RESPONDS="false"
if curl -s -H "Host: $DOMAIN" http://localhost | grep -q "Under Construction"; then
    # Virtualmin default page usually contains "Under Construction" or similar, 
    # but since we restored a backup, it might have the files we left.
    # If we created the backup with just a marker, the index might be default or missing.
    # Let's check for the marker file over HTTP if Apache is serving
    if curl -s -H "Host: $DOMAIN" "http://localhost/restore_proof.txt" | grep -q "$EXPECTED_MARKER"; then
        WEB_RESPONDS="true"
    elif curl -s -I -H "Host: $DOMAIN" http://localhost | grep -q "200 OK"; then
        WEB_RESPONDS="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "domain_exists": $DOMAIN_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "features": {
        "web": $FEATURE_WEB,
        "dns": $FEATURE_DNS,
        "mail": $FEATURE_MAIL,
        "mysql": $FEATURE_MYSQL
    },
    "marker_restored": $MARKER_RESTORED,
    "user_restored": $USER_RESTORED,
    "web_responds": $WEB_RESPONDS,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="