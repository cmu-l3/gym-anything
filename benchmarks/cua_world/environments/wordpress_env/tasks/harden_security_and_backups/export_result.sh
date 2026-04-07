#!/bin/bash
# Export script for harden_security_and_backups task

echo "=== Exporting harden_security_and_backups result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initial baseline
INITIAL_ADMIN_POST_COUNT=$(cat /tmp/initial_admin_post_count 2>/dev/null || echo "0")

# ============================================================
# Check User States
# ============================================================

# 1. Check if 'admin' was deleted
ADMIN_DELETED="false"
ADMIN_EXISTS=$(wp_db_query "SELECT COUNT(*) FROM wp_users WHERE user_login='admin'")
if [ "$ADMIN_EXISTS" -eq 0 ]; then
    ADMIN_DELETED="true"
    echo "User 'admin' successfully deleted."
else
    echo "User 'admin' still exists."
fi

# 2. Check if 'sec_admin' was created
SEC_ADMIN_CREATED="false"
SEC_ADMIN_ID=""
SEC_ADMIN_ROLE=""
SEC_ADMIN_EMAIL=""

SEC_ADMIN_ID=$(wp_db_query "SELECT ID FROM wp_users WHERE user_login='sec_admin' LIMIT 1")

if [ -n "$SEC_ADMIN_ID" ]; then
    SEC_ADMIN_CREATED="true"
    SEC_ADMIN_EMAIL=$(wp_db_query "SELECT user_email FROM wp_users WHERE ID=$SEC_ADMIN_ID")
    
    # Check role
    cd /var/www/html/wordpress
    SEC_ADMIN_ROLE=$(wp user get "$SEC_ADMIN_ID" --field=roles --allow-root 2>/dev/null || echo "")
    
    echo "User 'sec_admin' created (ID: $SEC_ADMIN_ID, Role: $SEC_ADMIN_ROLE)."
else
    echo "User 'sec_admin' NOT found."
fi

# 3. Check if content was reassigned
CONTENT_REASSIGNED="false"
SEC_ADMIN_POST_COUNT="0"

if [ -n "$SEC_ADMIN_ID" ]; then
    SEC_ADMIN_POST_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE post_author=$SEC_ADMIN_ID AND post_type IN ('post', 'page') AND post_status='publish'")
    echo "sec_admin owns $SEC_ADMIN_POST_COUNT published posts/pages (initial admin had $INITIAL_ADMIN_POST_COUNT)."
    
    if [ "$SEC_ADMIN_POST_COUNT" -ge "$INITIAL_ADMIN_POST_COUNT" ] && [ "$INITIAL_ADMIN_POST_COUNT" -gt 0 ]; then
        CONTENT_REASSIGNED="true"
        echo "Content successfully reassigned."
    fi
fi

# ============================================================
# Check Configuration and Plugins
# ============================================================

# 4. Check wp-config.php for DISALLOW_FILE_EDIT
FILE_EDITOR_DISABLED="false"
WP_CONFIG_PATH="/var/www/html/wordpress/wp-config.php"

if grep -q -iE "define\s*\(\s*['\"]DISALLOW_FILE_EDIT['\"]\s*,\s*true\s*\)" "$WP_CONFIG_PATH"; then
    FILE_EDITOR_DISABLED="true"
    echo "File editor disabled in wp-config.php."
else
    echo "File editor NOT disabled in wp-config.php."
fi

# 5. Check UpdraftPlus Activation
UPDRAFT_ACTIVE="false"
cd /var/www/html/wordpress
if wp plugin is-active updraftplus --allow-root 2>/dev/null; then
    UPDRAFT_ACTIVE="true"
    echo "UpdraftPlus is installed and active."
else
    echo "UpdraftPlus is NOT active."
fi

# ============================================================
# Export to JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "admin_deleted": $ADMIN_DELETED,
    "sec_admin_created": $SEC_ADMIN_CREATED,
    "sec_admin_role": "$SEC_ADMIN_ROLE",
    "sec_admin_email": "$SEC_ADMIN_EMAIL",
    "initial_admin_post_count": $INITIAL_ADMIN_POST_COUNT,
    "sec_admin_post_count": $SEC_ADMIN_POST_COUNT,
    "content_reassigned": $CONTENT_REASSIGNED,
    "file_editor_disabled": $FILE_EDITOR_DISABLED,
    "updraftplus_active": $UPDRAFT_ACTIVE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="