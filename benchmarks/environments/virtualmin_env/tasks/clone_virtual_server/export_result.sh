#!/bin/bash
# Note: Do not use set -e, we want to capture partial failures
echo "=== Exporting clone_virtual_server results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_DOMAIN="acmecorp-staging.test"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Domain Existence
DOMAIN_EXISTS=false
DOMAIN_ID=""
if virtualmin list-domains --name-only 2>/dev/null | grep -q "^${TARGET_DOMAIN}$"; then
    DOMAIN_EXISTS=true
    DOMAIN_ID=$(get_domain_id "$TARGET_DOMAIN")
fi

# 3. Check Enabled Features
WEB_ENABLED=false
DNS_ENABLED=false
MAIL_ENABLED=false
MYSQL_ENABLED=false
DOMAIN_HOME=""

if [ "$DOMAIN_EXISTS" = "true" ]; then
    INFO=$(virtualmin list-domains --domain "$TARGET_DOMAIN" --multiline 2>/dev/null)
    
    if echo "$INFO" | grep -qi "Website.*enabled\|Apache.*yes\|web:.*yes"; then WEB_ENABLED=true; fi
    if echo "$INFO" | grep -qi "DNS.*enabled\|DNS.*yes\|dns:.*yes"; then DNS_ENABLED=true; fi
    if echo "$INFO" | grep -qi "Mail.*enabled\|mail.*yes\|Mail for domain"; then MAIL_ENABLED=true; fi
    if echo "$INFO" | grep -qi "MySQL.*enabled\|mysql.*yes"; then MYSQL_ENABLED=true; fi
    
    DOMAIN_HOME=$(echo "$INFO" | grep "Home directory" | awk '{print $NF}')
fi

# 4. Check Content Copy (Anti-gaming)
FILE_COUNT=0
MARKER_FOUND=false
FILES_CREATED_DURING_TASK=false

if [ -n "$DOMAIN_HOME" ] && [ -d "$DOMAIN_HOME/public_html" ]; then
    FILE_COUNT=$(find "$DOMAIN_HOME/public_html" -type f 2>/dev/null | wc -l)
    
    # Check for the specific marker file we created in setup
    if [ -f "$DOMAIN_HOME/public_html/staging_test_marker.txt" ]; then
        MARKER_FOUND=true
    fi
    
    # Check timestamps
    NEWEST_FILE=$(find "$DOMAIN_HOME/public_html" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
    # Also check directory creation time
    DIR_TIME=$(stat -c %Y "$DOMAIN_HOME" 2>/dev/null || echo "0")
    
    if [ "${DIR_TIME%.*}" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK=true
    fi
fi

# 5. Check Database Existence
DB_EXISTS=false
DB_NAME=""
if [ "$MYSQL_ENABLED" = "true" ]; then
    # List databases for this domain
    DBS=$(virtualmin list-databases --domain "$TARGET_DOMAIN" --name-only 2>/dev/null)
    if [ -n "$DBS" ]; then
        DB_EXISTS=true
        DB_NAME=$(echo "$DBS" | head -1)
    fi
fi

# 6. Verify Password
# We verify this by attempting to authenticate to the API/Webmin with the new credentials
PASSWORD_VALID=false
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    --user "acmecorp-staging:StagingPass456!" \
    "https://localhost:10000/" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    PASSWORD_VALID=true
fi

# 7. Verify DNS Resolution (Internal)
DNS_RECORDS_EXIST=false
if [ "$DNS_ENABLED" = "true" ]; then
    if virtualmin get-dns --domain "$TARGET_DOMAIN" 2>/dev/null | grep -q "$TARGET_DOMAIN"; then
        DNS_RECORDS_EXIST=true
    fi
fi

# 8. Check if only one domain was added
INITIAL_COUNT=$(cat /tmp/initial_domain_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(virtualmin list-domains --name-only 2>/dev/null | wc -l)
DOMAINS_ADDED=$((CURRENT_COUNT - INITIAL_COUNT))

# 9. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "domain_exists": $DOMAIN_EXISTS,
    "features": {
        "web": $WEB_ENABLED,
        "dns": $DNS_ENABLED,
        "mail": $MAIL_ENABLED,
        "mysql": $MYSQL_ENABLED
    },
    "content_verification": {
        "file_count": $FILE_COUNT,
        "marker_found": $MARKER_FOUND,
        "created_during_task": $FILES_CREATED_DURING_TASK,
        "source_file_count": $(cat /tmp/source_file_count.txt 2>/dev/null || echo "0")
    },
    "database_verification": {
        "db_exists": $DB_EXISTS,
        "db_name": "$DB_NAME"
    },
    "dns_verification": {
        "records_exist": $DNS_RECORDS_EXIST
    },
    "security_verification": {
        "password_valid": $PASSWORD_VALID
    },
    "stats": {
        "domains_added": $DOMAINS_ADDED,
        "task_start": $TASK_START
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
echo "=== Export complete ==="