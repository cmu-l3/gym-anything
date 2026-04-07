#!/bin/bash
echo "=== Exporting Cohort Sync task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
COHORT_EXISTS="false"
COHORT_ID="0"
MEMBER_COUNT="0"
MEMBERS="[]"
ENROL_SYNC_EXISTS="false"
GROUP_CREATED="false"
FILE_UPLOADED="false"

# 1. Check Course
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='NURS200' LIMIT 1")

if [ -n "$COURSE_ID" ]; then
    # 2. Check Cohort
    COHORT_ID=$(moodle_query "SELECT id FROM mdl_cohort WHERE idnumber='NURS-F26' LIMIT 1")
    
    if [ -n "$COHORT_ID" ]; then
        COHORT_EXISTS="true"
        
        # 3. Check Members
        MEMBER_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=$COHORT_ID")
        
        # Get members as JSON array
        MEMBERS_RAW=$(moodle_query "SELECT u.username FROM mdl_cohort_members cm JOIN mdl_user u ON cm.userid = u.id WHERE cm.cohortid=$COHORT_ID")
        if [ -n "$MEMBERS_RAW" ]; then
            MEMBERS=$(echo "$MEMBERS_RAW" | jq -R -s -c 'split("\n") | map(select(length > 0))')
        fi
        
        # 4. Check Enrollment Method (Cohort sync)
        ENROL_METHOD=$(moodle_query "SELECT id FROM mdl_enrol WHERE courseid=$COURSE_ID AND enrol='cohort' AND customint1=$COHORT_ID LIMIT 1")
        if [ -n "$ENROL_METHOD" ]; then
            ENROL_SYNC_EXISTS="true"
        fi
    fi
    
    # 5. Check Group Creation (Cohort sync can automatically create a group)
    GROUP_ID=$(moodle_query "SELECT id FROM mdl_groups WHERE courseid=$COURSE_ID AND timecreated >= $TASK_START LIMIT 1")
    if [ -n "$GROUP_ID" ]; then
        GROUP_CREATED="true"
    fi
    
    # 6. Check File Upload
    FILE_EXISTS=$(moodle_query "SELECT id FROM mdl_resource WHERE course=$COURSE_ID AND name LIKE '%Clinical Skills%' LIMIT 1")
    if [ -n "$FILE_EXISTS" ]; then
        FILE_UPLOADED="true"
    fi
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "course_id": "$COURSE_ID",
    "cohort_exists": $COHORT_EXISTS,
    "member_count": $MEMBER_COUNT,
    "members": $MEMBERS,
    "enrol_sync_exists": $ENROL_SYNC_EXISTS,
    "group_created": $GROUP_CREATED,
    "file_uploaded": $FILE_UPLOADED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="