#!/bin/bash
echo "=== Exporting Annual Survey Rollover Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Source SID (from setup)
SOURCE_SID=$(cat /tmp/source_survey_sid.txt 2>/dev/null || echo "0")

# 1. Find the NEW survey ID (Employee Pulse 2025)
# We look for the newest survey with the correct title
TARGET_SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title, s.active 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE sl.surveyls_title LIKE 'Employee Pulse 2025' 
ORDER BY s.sid DESC LIMIT 1")

TARGET_SID=""
TARGET_TITLE=""
TARGET_ACTIVE="N"
TARGET_FOUND="false"

if [ -n "$TARGET_SURVEY_DATA" ]; then
    TARGET_SID=$(echo "$TARGET_SURVEY_DATA" | awk '{print $1}')
    TARGET_TITLE=$(echo "$TARGET_SURVEY_DATA" | cut -f2) # Assuming tab separation
    TARGET_ACTIVE=$(echo "$TARGET_SURVEY_DATA" | awk '{print $NF}')
    TARGET_FOUND="true"
fi

# 2. Check Integrity of Source Survey (Employee Pulse 2024)
# It should still exist and still have the '2024 Initiatives' group
SOURCE_EXISTS="false"
SOURCE_INTACT="false"

if [ "$SOURCE_SID" != "0" ]; then
    CHECK_SOURCE=$(limesurvey_query "SELECT count(*) FROM lime_surveys WHERE sid=$SOURCE_SID")
    if [ "$CHECK_SOURCE" -gt 0 ]; then
        SOURCE_EXISTS="true"
        # Check if the old group is still there
        OLD_GROUP_COUNT=$(limesurvey_query "SELECT count(*) FROM lime_groups WHERE sid=$SOURCE_SID AND group_name='2024 Initiatives'")
        if [ "$OLD_GROUP_COUNT" -gt 0 ]; then
            SOURCE_INTACT="true"
        fi
    fi
fi

# 3. Check Target Survey Structure
OBSOLETE_GROUP_GONE="false"
NEW_GROUP_FOUND="false"
Q1_FOUND="false"
Q2_FOUND="false"
Q1_TYPE=""
Q2_TYPE=""

if [ "$TARGET_FOUND" = "true" ]; then
    # Check Obsolete Group
    CHECK_OBSOLETE=$(limesurvey_query "SELECT count(*) FROM lime_groups WHERE sid=$TARGET_SID AND group_name='2024 Initiatives'")
    if [ "$CHECK_OBSOLETE" -eq 0 ]; then
        OBSOLETE_GROUP_GONE="true"
    fi

    # Check New Group
    NEW_GROUP_GID=$(limesurvey_query "SELECT gid FROM lime_groups WHERE sid=$TARGET_SID AND group_name='2025 Strategic Focus' LIMIT 1")
    if [ -n "$NEW_GROUP_GID" ]; then
        NEW_GROUP_FOUND="true"
        
        # Check Questions in the new survey (can be anywhere, but ideally in the new group)
        # Q1: AI_USAGE
        Q1_DATA=$(limesurvey_query "SELECT type FROM lime_questions WHERE sid=$TARGET_SID AND title='AI_USAGE'")
        if [ -n "$Q1_DATA" ]; then
            Q1_FOUND="true"
            Q1_TYPE="$Q1_DATA"
        fi

        # Q2: INNOVATION_IDEA
        Q2_DATA=$(limesurvey_query "SELECT type FROM lime_questions WHERE sid=$TARGET_SID AND title='INNOVATION_IDEA'")
        if [ -n "$Q2_DATA" ]; then
            Q2_FOUND="true"
            Q2_TYPE="$Q2_DATA"
        fi
    fi
fi

# Create JSON result
JSON_CONTENT=$(cat << EOF
{
    "source_sid": "$SOURCE_SID",
    "source_exists": $SOURCE_EXISTS,
    "source_intact": $SOURCE_INTACT,
    "target_found": $TARGET_FOUND,
    "target_sid": "$TARGET_SID",
    "target_title": "$TARGET_TITLE",
    "target_active": "$TARGET_ACTIVE",
    "obsolete_group_gone": $OBSOLETE_GROUP_GONE,
    "new_group_found": $NEW_GROUP_FOUND,
    "q1_found": $Q1_FOUND,
    "q1_type": "$Q1_TYPE",
    "q2_found": $Q2_FOUND,
    "q2_type": "$Q2_TYPE",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

export_json_result "$JSON_CONTENT" "/tmp/task_result.json"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="