#!/bin/bash
echo "=== Exporting install_wordpress_script results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Virtualmin Registry
# Does Virtualmin think WordPress is installed?
VIRTUALMIN_LIST=$(virtualmin list-scripts --domain acmecorp.test 2>/dev/null || true)
IS_REGISTERED="false"
if echo "$VIRTUALMIN_LIST" | grep -qi "wordpress"; then
    IS_REGISTERED="true"
fi

# 2. Check Filesystem
# Look for wp-config.php in the expected location
EXPECTED_PATH="/home/acmecorp/public_html/blog/wp-config.php"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_MTIME="0"

# Also check root or other paths for partial credit
ACTUAL_PATH=""
if [ -f "$EXPECTED_PATH" ]; then
    ACTUAL_PATH="$EXPECTED_PATH"
elif [ -f "/home/acmecorp/public_html/wp-config.php" ]; then
    ACTUAL_PATH="/home/acmecorp/public_html/wp-config.php"
fi

if [ -n "$ACTUAL_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$ACTUAL_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Database Content
# We need to find the database name. It's usually defined in wp-config.php.
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""

if [ -n "$ACTUAL_PATH" ]; then
    # Extract DB info from wp-config.php
    DB_NAME=$(grep "DB_NAME" "$ACTUAL_PATH" | cut -d "'" -f 4)
    DB_USER=$(grep "DB_USER" "$ACTUAL_PATH" | cut -d "'" -f 4)
    DB_PASS=$(grep "DB_PASSWORD" "$ACTUAL_PATH" | cut -d "'" -f 4)
fi

DB_VALID="false"
WP_TITLE=""
WP_SITEURL=""
WP_ADMIN_FOUND="false"
TABLE_COUNT="0"

if [ -n "$DB_NAME" ]; then
    # Verify tables exist
    TABLE_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" 2>/dev/null || echo "0")
    
    if [ "$TABLE_COUNT" -gt 5 ]; then
        DB_VALID="true"
        
        # Get Site Title
        WP_TITLE=$(mysql -u root -pGymAnything123! -N -e "SELECT option_value FROM \`${DB_NAME}\`.wp_options WHERE option_name='blogname';" 2>/dev/null || true)
        
        # Get Site URL (to verify path)
        WP_SITEURL=$(mysql -u root -pGymAnything123! -N -e "SELECT option_value FROM \`${DB_NAME}\`.wp_options WHERE option_name='siteurl';" 2>/dev/null || true)
        
        # Check for admin user
        # We look for the login 'wpadmin'
        ADMIN_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM \`${DB_NAME}\`.wp_users WHERE user_login='wpadmin';" 2>/dev/null || echo "0")
        if [ "$ADMIN_COUNT" -gt 0 ]; then
            WP_ADMIN_FOUND="true"
        fi
    fi
fi

# 4. Anti-gaming: Script count increase
INITIAL_COUNT=$(cat /tmp/initial_script_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(virtualmin list-scripts --domain acmecorp.test 2>/dev/null | grep -c "WordPress" || echo "0")
SCRIPT_COUNT_INCREASED="false"
if [ "$FINAL_COUNT" -gt "$INITIAL_COUNT" ]; then
    SCRIPT_COUNT_INCREASED="true"
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "is_registered_in_virtualmin": $IS_REGISTERED,
    "file_exists": $FILE_EXISTS,
    "file_path": "$ACTUAL_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "db_valid": $DB_VALID,
    "table_count": $TABLE_COUNT,
    "wp_title": "$(json_escape "$WP_TITLE")",
    "wp_siteurl": "$(json_escape "$WP_SITEURL")",
    "wp_admin_found": $WP_ADMIN_FOUND,
    "script_count_increased": $SCRIPT_COUNT_INCREASED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="