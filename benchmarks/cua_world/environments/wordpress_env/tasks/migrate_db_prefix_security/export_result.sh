#!/bin/bash
# Export script for migrate_db_prefix_security task
# Gathers verification data about the wp-config file, database tables, and site functionality

echo "=== Exporting migrate_db_prefix_security result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check wp-config.php for the table prefix
WP_CONFIG_FILE="/var/www/html/wordpress/wp-config.php"
CONFIG_PREFIX=""

if [ -f "$WP_CONFIG_FILE" ]; then
    # Extract the table_prefix value (e.g., $table_prefix = 'sec24_';)
    CONFIG_PREFIX=$(grep "table_prefix" "$WP_CONFIG_FILE" | sed -n "s/.*['\"]\([^'\"]*\)['\"].*/\1/p" | head -1)
    echo "Found table_prefix in wp-config.php: '$CONFIG_PREFIX'"
else
    echo "ERROR: wp-config.php not found!"
fi

# 2. Check Database Tables
echo "Checking database tables..."
# Using mysql directly via docker to avoid WP-CLI errors if site is broken
DB_EXEC="docker exec wordpress-mariadb mysql -u wordpress -pwordpresspass wordpress -N -e"

WP_TABLE_COUNT=$($DB_EXEC "SHOW TABLES LIKE 'wp_%'" 2>/dev/null | wc -l)
SEC24_TABLE_COUNT=$($DB_EXEC "SHOW TABLES LIKE 'sec24_%'" 2>/dev/null | wc -l)

echo "Old 'wp_' tables remaining: $WP_TABLE_COUNT"
echo "New 'sec24_' tables found: $SEC24_TABLE_COUNT"

# 3. Check Options Migration (sec24_user_roles)
OPTIONS_MIGRATED_COUNT=$($DB_EXEC "SELECT COUNT(*) FROM sec24_options WHERE option_name='sec24_user_roles'" 2>/dev/null || echo "0")
echo "Migrated options count (sec24_user_roles): $OPTIONS_MIGRATED_COUNT"

# 4. Check Usermeta Migration (sec24_capabilities)
USERMETA_MIGRATED_COUNT=$($DB_EXEC "SELECT COUNT(*) FROM sec24_usermeta WHERE meta_key='sec24_capabilities'" 2>/dev/null || echo "0")
echo "Migrated usermeta count (sec24_capabilities): $USERMETA_MIGRATED_COUNT"

# 5. Check Site Functionality using WP-CLI
# If the prefix and options are properly synced, wp-cli will be able to load users
echo "Testing site functionality via WP-CLI..."
WP_CLI_WORKS="false"
cd /var/www/html/wordpress

# Test if WP-CLI can successfully query the admin user
if wp user list --field=user_login --allow-root 2>/dev/null | grep -q "admin"; then
    WP_CLI_WORKS="true"
    echo "WP-CLI successfully queried users - site is functional."
else
    echo "WP-CLI failed to query users - site may be broken or prefix is misconfigured."
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_prefix": "$(json_escape "$CONFIG_PREFIX")",
    "wp_table_count": $WP_TABLE_COUNT,
    "sec24_table_count": $SEC24_TABLE_COUNT,
    "options_migrated_count": $OPTIONS_MIGRATED_COUNT,
    "usermeta_migrated_count": $USERMETA_MIGRATED_COUNT,
    "site_functional": $WP_CLI_WORKS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/migrate_db_prefix_result.json 2>/dev/null || sudo rm -f /tmp/migrate_db_prefix_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/migrate_db_prefix_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/migrate_db_prefix_result.json
chmod 666 /tmp/migrate_db_prefix_result.json 2>/dev/null || sudo chmod 666 /tmp/migrate_db_prefix_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/migrate_db_prefix_result.json"
cat /tmp/migrate_db_prefix_result.json
echo ""
echo "=== Export complete ==="