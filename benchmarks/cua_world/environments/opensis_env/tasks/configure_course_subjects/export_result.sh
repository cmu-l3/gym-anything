#!/bin/bash
set -euo pipefail

echo "=== Exporting configure_course_subjects result ==="

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Retrieve stored table name
TABLE_NAME=$(cat /tmp/subject_table_name.txt 2>/dev/null || echo "course_subjects")
INITIAL_MAX_ID=$(cat /tmp/initial_max_id.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_subject_count.txt 2>/dev/null || echo "0")

# Take final screenshot
scrot /tmp/task_final.png 2>/dev/null || true

# Query for the specific subjects we asked for
# Using JSON_ARRAYAGG if available, or manual construction if MariaDB version is old
# We'll stick to simple select and parse in Python or simple CSV output

# 1. Check for "Computer Science"
CS_RECORD=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT subject_id, title FROM $TABLE_NAME WHERE title LIKE 'Computer Science' LIMIT 1;" 2>/dev/null || echo "")

# 2. Check for "Fine Arts"
FA_RECORD=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT subject_id, title FROM $TABLE_NAME WHERE title LIKE 'Fine Arts' LIMIT 1;" 2>/dev/null || echo "")

# 3. Get total current count
CURRENT_COUNT=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT COUNT(*) FROM $TABLE_NAME;" 2>/dev/null || echo "0")

# 4. Check for ANY new records created during this session (ID > Initial Max)
NEW_RECORDS_COUNT=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT COUNT(*) FROM $TABLE_NAME WHERE subject_id > $INITIAL_MAX_ID;" 2>/dev/null || echo "0")

# Parse CS Record
CS_FOUND="false"
CS_ID="0"
if [ -n "$CS_RECORD" ]; then
    CS_FOUND="true"
    CS_ID=$(echo "$CS_RECORD" | awk '{print $1}')
fi

# Parse FA Record
FA_FOUND="false"
FA_ID="0"
if [ -n "$FA_RECORD" ]; then
    FA_FOUND="true"
    FA_ID=$(echo "$FA_RECORD" | awk '{print $1}')
fi

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "table_name": "$TABLE_NAME",
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "initial_max_id": $INITIAL_MAX_ID,
    "new_records_count": $NEW_RECORDS_COUNT,
    "computer_science": {
        "found": $CS_FOUND,
        "id": $CS_ID
    },
    "fine_arts": {
        "found": $FA_FOUND,
        "id": $FA_ID
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json