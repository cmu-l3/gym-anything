#!/bin/bash
echo "=== Exporting rename_virtual_server results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather System State
NEW_DOMAIN="acmetech.test"
OLD_DOMAIN="acmecorp.test"

# Check domains existence
NEW_EXISTS="false"
if virtualmin_domain_exists "$NEW_DOMAIN"; then
    NEW_EXISTS="true"
fi

OLD_EXISTS="false"
if virtualmin_domain_exists "$OLD_DOMAIN"; then
    OLD_EXISTS="true"
fi

# Check features for new domain
WEB_ENABLED="false"
DNS_ENABLED="false"
MAIL_ENABLED="false"
MYSQL_ENABLED="false"
HOME_DIR=""
UNIX_USER=""

if [ "$NEW_EXISTS" = "true" ]; then
    FEATURES=$(virtualmin list-domains --domain "$NEW_DOMAIN" --multiline 2>/dev/null)
    
    if echo "$FEATURES" | grep -qi "Web: Yes"; then WEB_ENABLED="true"; fi
    if echo "$FEATURES" | grep -qi "DNS: Yes"; then DNS_ENABLED="true"; fi
    if echo "$FEATURES" | grep -qi "Mail: Yes"; then MAIL_ENABLED="true"; fi
    if echo "$FEATURES" | grep -qi "MySQL database: Yes"; then MYSQL_ENABLED="true"; fi
    
    HOME_DIR=$(echo "$FEATURES" | grep -i "Home directory:" | cut -d: -f2 | tr -d ' ')
    UNIX_USER=$(echo "$FEATURES" | grep -i "Username:" | cut -d: -f2 | tr -d ' ')
fi

# Check MySQL Database Name (Direct Check)
# Look for a database that contains 'acmetech'
DB_MATCH_COUNT=$(mysql -u root -pGymAnything123! -N -e "SHOW DATABASES LIKE '%acmetech%';" 2>/dev/null | wc -l)
DB_OLD_COUNT=$(mysql -u root -pGymAnything123! -N -e "SHOW DATABASES LIKE '%acmecorp%';" 2>/dev/null | wc -l)

# Check DNS Zone File
ZONE_FILE_EXISTS="false"
if [ -f "/var/lib/bind/${NEW_DOMAIN}.hosts" ] || [ -f "/etc/bind/${NEW_DOMAIN}.hosts" ]; then
    ZONE_FILE_EXISTS="true"
fi

# Check Apache Config
APACHE_CONF_EXISTS="false"
if [ -f "/etc/apache2/sites-available/${NEW_DOMAIN}.conf" ]; then
    APACHE_CONF_EXISTS="true"
fi

# Check Timestamps (Anti-Gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HOME_DIR_MTIME="0"
if [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ]; then
    HOME_DIR_MTIME=$(stat -c %Y "$HOME_DIR" 2>/dev/null || echo "0")
fi

CREATED_DURING_TASK="false"
if [ "$HOME_DIR_MTIME" -ge "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "new_domain_exists": $NEW_EXISTS,
    "old_domain_exists": $OLD_EXISTS,
    "features": {
        "web": $WEB_ENABLED,
        "dns": $DNS_ENABLED,
        "mail": $MAIL_ENABLED,
        "mysql": $MYSQL_ENABLED
    },
    "artifacts": {
        "home_dir": "$HOME_DIR",
        "unix_user": "$UNIX_USER",
        "db_match_count": $DB_MATCH_COUNT,
        "db_old_count": $DB_OLD_COUNT,
        "zone_file_exists": $ZONE_FILE_EXISTS,
        "apache_conf_exists": $APACHE_CONF_EXISTS
    },
    "timestamps": {
        "task_start": $TASK_START,
        "home_dir_mtime": $HOME_DIR_MTIME,
        "created_during_task": $CREATED_DURING_TASK
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json