#!/bin/bash
echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if table exists and get row count
ROW_COUNT=$(mysql -u root socioboard -N -e "SELECT COUNT(*) FROM banned_keywords;" 2>/dev/null || echo "0")
if [ "$ROW_COUNT" -gt 0 ]; then
    TABLE_EXISTS="true"
else
    TABLE_EXISTS="false"
fi

# 2. Check if trigger exists
TRIGGER_EXISTS_DB=$(mysql -u root socioboard -N -e "SELECT COUNT(*) FROM information_schema.triggers WHERE TRIGGER_NAME='enforce_clean_team_names' AND EVENT_OBJECT_TABLE='team_informations' AND TRIGGER_SCHEMA='socioboard';" 2>/dev/null || echo "0")
if [ "$TRIGGER_EXISTS_DB" -eq 1 ]; then
    TRIGGER_EXISTS="true"
else
    TRIGGER_EXISTS="false"
fi

# Fetch a valid admin ID to use for INSERT tests
ADMIN_ID=$(mysql -u root socioboard -N -e "SELECT user_id FROM user_details LIMIT 1;" 2>/dev/null)
if [ -z "$ADMIN_ID" ]; then ADMIN_ID="1"; fi

# 3. Test True Positive (Rejection of bad word)
# Get an actual bad word from the agent's table
BAD_WORD=$(mysql -u root socioboard -N -e "SELECT word FROM banned_keywords LIMIT 1;" 2>/dev/null)
if [ -z "$BAD_WORD" ] || [ "$BAD_WORD" = "0" ]; then
    BAD_WORD="fallbackbadword"
fi

mysql -u root socioboard -e "INSERT INTO team_informations (team_name, team_logo, team_description, team_admin_id) VALUES ('$BAD_WORD Marketing Team', 'logo.png', 'desc', $ADMIN_ID);" 2> /tmp/bad_insert_err.txt
BAD_INSERT_ERR=$(cat /tmp/bad_insert_err.txt)

if echo "$BAD_INSERT_ERR" | grep -q "45000"; then
    # SQLSTATE 45000 detected
    BLOCKED_BAD="true"
elif echo "$BAD_INSERT_ERR" | grep -q "1644"; then
    # MySQL Error code 1644 (Unhandled user-defined exception) detected
    BLOCKED_BAD="true"
else
    BLOCKED_BAD="false"
fi

# 4. Test True Negative (Acceptance of good word)
GOOD_TEAM_NAME="Clean Corporate Team $(date +%s)"
mysql -u root socioboard -e "INSERT INTO team_informations (team_name, team_logo, team_description, team_admin_id) VALUES ('$GOOD_TEAM_NAME', 'logo.png', 'desc', $ADMIN_ID);" 2> /tmp/good_insert_err.txt
GOOD_INSERT_ERR=$(cat /tmp/good_insert_err.txt)

# Verify the good team was actually inserted
GOOD_INSERTED=$(mysql -u root socioboard -N -e "SELECT COUNT(*) FROM team_informations WHERE team_name='$GOOD_TEAM_NAME';" 2>/dev/null || echo "0")
if [ "$GOOD_INSERTED" -eq 1 ]; then
    ALLOWED_GOOD="true"
else
    ALLOWED_GOOD="false"
fi

# Cleanup the good test team so we don't pollute the DB
mysql -u root socioboard -e "DELETE FROM team_informations WHERE team_name='$GOOD_TEAM_NAME';" 2>/dev/null

# Clean strings for JSON
BAD_ERR_CLEAN=$(echo "$BAD_INSERT_ERR" | tr -d '\n' | tr -d '"' | sed 's/\\/\\\\/g')
GOOD_ERR_CLEAN=$(echo "$GOOD_INSERT_ERR" | tr -d '\n' | tr -d '"' | sed 's/\\/\\\\/g')

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "table_exists": $TABLE_EXISTS,
    "row_count": $ROW_COUNT,
    "trigger_exists": $TRIGGER_EXISTS,
    "blocked_bad": $BLOCKED_BAD,
    "bad_insert_error": "$BAD_ERR_CLEAN",
    "allowed_good": $ALLOWED_GOOD,
    "good_insert_error": "$GOOD_ERR_CLEAN",
    "tested_bad_word": "$BAD_WORD",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="