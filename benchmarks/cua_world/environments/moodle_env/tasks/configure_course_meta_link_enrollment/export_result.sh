#!/bin/bash
# Export script for Course Meta Link task

echo "=== Exporting Course Meta Link Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read IDs
PARENT_ID=$(cat /tmp/parent_course_id 2>/dev/null || echo "0")
CHILD_ID=$(cat /tmp/child_course_id 2>/dev/null || echo "0")

echo "Checking configuration between Parent ($PARENT_ID) and Child ($CHILD_ID)..."

# 1. Check if Meta Link method exists in Child Course pointing to Parent
# We look for enrol='meta' and customint1=PARENT_ID
META_LINK_DATA=$(moodle_query "
    SELECT id, status, customint1, enrol 
    FROM mdl_enrol 
    WHERE courseid=$CHILD_ID AND enrol='meta' AND customint1=$PARENT_ID 
    LIMIT 1
")

META_EXISTS="false"
META_STATUS="1" # 1 = Disabled by default logic (though 0 is enabled in DB)
META_SOURCE_ID="0"

if [ -n "$META_LINK_DATA" ]; then
    META_EXISTS="true"
    META_ID=$(echo "$META_LINK_DATA" | cut -f1)
    META_STATUS=$(echo "$META_LINK_DATA" | cut -f2) # 0=Enabled, 1=Disabled
    META_SOURCE_ID=$(echo "$META_LINK_DATA" | cut -f3)
    echo "Meta link found: ID=$META_ID, Status=$META_STATUS, Source=$META_SOURCE_ID"
else
    echo "No specific meta link found between these courses."
    # Check if ANY meta link exists (for debugging/partial credit)
    ANY_META=$(moodle_query "SELECT count(*) FROM mdl_enrol WHERE courseid=$CHILD_ID AND enrol='meta'")
    echo "Total meta links in child course: $ANY_META"
fi

# 2. Check Enrollment Sync (Are students actually in the child course now?)
INITIAL_COUNT=$(cat /tmp/initial_child_enrollment 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_enrollment_count "$CHILD_ID" 2>/dev/null || echo "0")

echo "Enrollment Count: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT"

# 3. Check specific test users (bio_student1)
# Get ID of bio_student1
STUDENT_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='bio_student1'" | tr -d '[:space:]')
STUDENT_ENROLLED="false"

if [ -n "$STUDENT_ID" ]; then
    # Check if enrolled via meta
    IS_IN_META=$(moodle_query "
        SELECT COUNT(*) 
        FROM mdl_user_enrolments ue 
        JOIN mdl_enrol e ON ue.enrolid = e.id 
        WHERE ue.userid=$STUDENT_ID AND e.courseid=$CHILD_ID AND e.enrol='meta'
    ")
    if [ "$IS_IN_META" -gt 0 ]; then
        STUDENT_ENROLLED="true"
        echo "bio_student1 is enrolled via meta link."
    else
        echo "bio_student1 is NOT enrolled via meta link."
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/meta_link_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "parent_course_id": $PARENT_ID,
    "child_course_id": $CHILD_ID,
    "meta_link_exists": $META_EXISTS,
    "meta_link_status": $META_STATUS,
    "meta_source_id": $META_SOURCE_ID,
    "initial_enrollment": $INITIAL_COUNT,
    "current_enrollment": $CURRENT_COUNT,
    "test_student_synced": $STUDENT_ENROLLED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/meta_link_result.json

echo ""
cat /tmp/meta_link_result.json
echo ""
echo "=== Export Complete ==="