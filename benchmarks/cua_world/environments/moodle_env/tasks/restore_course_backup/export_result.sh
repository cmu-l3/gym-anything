#!/bin/bash
echo "=== Exporting Restore Course Backup Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HUMANITIES_ID=$(cat /tmp/humanities_id.txt 2>/dev/null || echo "0")

# Query the database for the newly restored course using the requested shortname
COURSE_DATA=$(moodle_query "SELECT id, category, fullname, timecreated FROM mdl_course WHERE shortname='DL101-F26' LIMIT 1")

COURSE_FOUND="false"
COURSE_ID="0"
CATEGORY_ID="0"
FULLNAME=""
TIMECREATED="0"
MODULE_COUNT="0"

if [ -n "$COURSE_DATA" ]; then
    COURSE_FOUND="true"
    COURSE_ID=$(echo "$COURSE_DATA" | cut -f1)
    CATEGORY_ID=$(echo "$COURSE_DATA" | cut -f2)
    FULLNAME=$(echo "$COURSE_DATA" | cut -f3)
    TIMECREATED=$(echo "$COURSE_DATA" | cut -f4)
    
    # Count the number of activity modules in the course to verify it's not just an empty shell
    MODULE_COUNT=$(moodle_query "SELECT count(*) FROM mdl_course_modules WHERE course='$COURSE_ID'")
fi

# Escape fullname for JSON safely
FULLNAME_ESCAPED=$(echo "$FULLNAME" | sed 's/"/\\"/g')

# Build the JSON result safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "humanities_id": $HUMANITIES_ID,
    "course_found": $COURSE_FOUND,
    "course_id": $COURSE_ID,
    "category_id": $CATEGORY_ID,
    "fullname": "$FULLNAME_ESCAPED",
    "timecreated": $TIMECREATED,
    "module_count": $MODULE_COUNT
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

rm -f "$TEMP_JSON"

echo "Exported state:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="