#!/bin/bash
echo "=== Exporting create_server_alias result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TARGET_ALIAS="acme-corp.test"
PARENT_DOMAIN="acmecorp.test"

# 1. Check if domain exists
DOMAIN_EXISTS="false"
if virtualmin_domain_exists "$TARGET_ALIAS"; then
    DOMAIN_EXISTS="true"
fi

# 2. Get Domain Details (Multiline format)
DETAILS_FILE="/tmp/alias_details.txt"
virtualmin list-domains --domain "$TARGET_ALIAS" --multiline > "$DETAILS_FILE" 2>/dev/null || true

# 3. Check for specific features
IS_ALIAS="false"
PARENT_MATCH="false"
HAS_WEB="false"
HAS_DNS="false"
HAS_MAIL="false"

if [ "$DOMAIN_EXISTS" = "true" ]; then
    # Check if it's an alias
    if grep -qi "Alias of" "$DETAILS_FILE" || grep -qi "Parent domain" "$DETAILS_FILE"; then
        IS_ALIAS="true"
    fi
    
    # Check parent
    if grep -i "Alias of" "$DETAILS_FILE" | grep -q "$PARENT_DOMAIN" || \
       grep -i "Parent domain" "$DETAILS_FILE" | grep -q "$PARENT_DOMAIN"; then
        PARENT_MATCH="true"
    fi

    # Check features
    # Note: Virtualmin output format varies slightly by version, checking for "Feature: [Enabled]" patterns
    if grep -qi "Web: Enabled" "$DETAILS_FILE" || grep -qi "HTML directory" "$DETAILS_FILE"; then
        HAS_WEB="true"
    fi
    if grep -qi "DNS: Enabled" "$DETAILS_FILE" || grep -qi "DNS domain: Enabled" "$DETAILS_FILE"; then
        HAS_DNS="true"
    fi
    if grep -qi "Mail: Enabled" "$DETAILS_FILE" || grep -qi "Mail domain: Enabled" "$DETAILS_FILE"; then
        HAS_MAIL="true"
    fi
fi

# 4. Check Apache Config (Secondary verification for Web)
APACHE_CONFIGURED="false"
if grep -r "$TARGET_ALIAS" /etc/apache2/sites-enabled/ 2>/dev/null | grep -qi "ServerAlias"; then
    APACHE_CONFIGURED="true"
fi

# 5. Check DNS Zone (Secondary verification for DNS)
DNS_ZONE_EXISTS="false"
# BIND zone files usually in /var/lib/bind or /etc/bind. Virtualmin usually names them domain.hosts
if [ -f "/var/lib/bind/$TARGET_ALIAS.hosts" ] || [ -f "/etc/bind/$TARGET_ALIAS.hosts" ] || \
   grep -q "$TARGET_ALIAS" "/var/lib/bind/$PARENT_DOMAIN.hosts" 2>/dev/null; then
    DNS_ZONE_EXISTS="true"
fi

# 6. Check Creation Timestamp
# We check if the domain folder was created after task start
CREATED_DURING_TASK="false"
# Virtualmin usually creates /home/user/domains/alias.test or similar for logs, 
# but for simple aliases, it might share the parent's home. 
# Best check is seeing it wasn't in initial_domains.txt
if ! grep -q "^${TARGET_ALIAS}$" /tmp/initial_domains.txt 2>/dev/null && [ "$DOMAIN_EXISTS" = "true" ]; then
    CREATED_DURING_TASK="true"
fi

# 7. Final Screenshot
take_screenshot /tmp/task_final.png

# 8. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "domain_exists": $DOMAIN_EXISTS,
    "is_alias": $IS_ALIAS,
    "parent_match": $PARENT_MATCH,
    "has_web": $HAS_WEB,
    "has_dns": $HAS_DNS,
    "has_mail": $HAS_MAIL,
    "apache_configured": $APACHE_CONFIGURED,
    "dns_zone_exists": $DNS_ZONE_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move and set permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="