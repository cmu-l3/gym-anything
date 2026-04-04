#!/bin/bash
echo "=== Exporting create_database_user task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# 1. Check if user exists
# ---------------------------------------------------------------
USER_EXISTS_LOCALHOST=$(virtualmin_db_query "SELECT COUNT(*) FROM mysql.user WHERE User='reports_reader' AND Host='localhost';" | tr -d '[:space:]')
USER_EXISTS_WILDCARD=$(virtualmin_db_query "SELECT COUNT(*) FROM mysql.user WHERE User='reports_reader' AND Host='%';" | tr -d '[:space:]')
USER_EXISTS_ANY=$(virtualmin_db_query "SELECT COUNT(*) FROM mysql.user WHERE User='reports_reader';" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 2. Check password authentication
# ---------------------------------------------------------------
AUTH_SUCCESS="false"
if mysql -u reports_reader -p'R3p0rt$2024!' -h localhost -e "SELECT 1;" >/dev/null 2>&1; then
    AUTH_SUCCESS="true"
fi

# ---------------------------------------------------------------
# 3. Check Privileges (Grants)
# ---------------------------------------------------------------
HAS_SELECT="false"
HAS_WRITE="false"
WRITE_DETAILS=""
GRANT_OUTPUT=""

if [ "$AUTH_SUCCESS" = "true" ]; then
    # Test SELECT permission actually works
    if mysql -u reports_reader -p'R3p0rt$2024!' -h localhost -D acmecorp -e "SELECT COUNT(*) FROM site_visitors;" >/dev/null 2>&1; then
        HAS_SELECT="true"
    fi

    # Test WRITE permissions (should fail)
    INSERT_TEST=$(mysql -u reports_reader -p'R3p0rt$2024!' -h localhost -D acmecorp -e "INSERT INTO site_visitors (visitor_ip, page_url) VALUES ('1.1.1.1', '/test');" 2>&1)
    if ! echo "$INSERT_TEST" | grep -qi "denied"; then
        HAS_WRITE="true"
        WRITE_DETAILS="${WRITE_DETAILS}INSERT_ALLOWED "
    fi
    
    DELETE_TEST=$(mysql -u reports_reader -p'R3p0rt$2024!' -h localhost -D acmecorp -e "DELETE FROM site_visitors WHERE id=1;" 2>&1)
    if ! echo "$DELETE_TEST" | grep -qi "denied"; then
        HAS_WRITE="true"
        WRITE_DETAILS="${WRITE_DETAILS}DELETE_ALLOWED "
    fi

    # Capture grants for debugging/verification
    GRANT_OUTPUT=$(mysql -u root -p'GymAnything123!' -e "SHOW GRANTS FOR 'reports_reader'@'localhost';" 2>/dev/null | tr '\n' ';')
else
    # Fallback: Check grants via root if auth failed but user exists
    if [ "$USER_EXISTS_LOCALHOST" = "1" ]; then
        GRANT_OUTPUT=$(mysql -u root -p'GymAnything123!' -e "SHOW GRANTS FOR 'reports_reader'@'localhost';" 2>/dev/null | tr '\n' ';')
        
        if echo "$GRANT_OUTPUT" | grep -i "ON \`acmecorp\`" | grep -i "SELECT"; then
             # User has select in grants, but maybe password was wrong
             HAS_SELECT="true_but_auth_failed"
        fi
    fi
fi

# ---------------------------------------------------------------
# 4. Anti-gaming: Check user count change
# ---------------------------------------------------------------
INITIAL_COUNT=$(cat /tmp/initial_mysql_user_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM mysql.user;" | tr -d '[:space:]')
USER_COUNT_DIFF=$((CURRENT_COUNT - INITIAL_COUNT))

# ---------------------------------------------------------------
# 5. Create JSON Result
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "user_exists_localhost": $([ "$USER_EXISTS_LOCALHOST" = "1" ] && echo "true" || echo "false"),
    "user_exists_wildcard": $([ "$USER_EXISTS_WILDCARD" = "1" ] && echo "true" || echo "false"),
    "user_exists_any": $([ "$USER_EXISTS_ANY" -gt 0 ] && echo "true" || echo "false"),
    "auth_success": $AUTH_SUCCESS,
    "has_select_privilege": "$HAS_SELECT",
    "has_write_privilege": $HAS_WRITE,
    "write_details": "$WRITE_DETAILS",
    "grants_debug": "$(json_escape "$GRANT_OUTPUT")",
    "user_count_diff": $USER_COUNT_DIFF,
    "task_duration": $((TASK_END - TASK_START)),
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