#!/bin/bash
# Export script for Create Cohort Enrollment task

echo "=== Exporting Create Cohort Enrollment Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Verify Cohort Existence
echo "Checking for cohort..."
# Query for cohort by ID Number first (most reliable)
COHORT_DATA=$(moodle_query "SELECT id, name, idnumber, timecreated FROM mdl_cohort WHERE idnumber='BIOMAJ-F25'")

# If not found by ID number, try name
if [ -z "$COHORT_DATA" ]; then
    COHORT_DATA=$(moodle_query "SELECT id, name, idnumber, timecreated FROM mdl_cohort WHERE name LIKE '%Biology Majors Fall 2025%' LIMIT 1")
fi

COHORT_FOUND="false"
COHORT_ID=""
COHORT_NAME=""
COHORT_IDNUMBER=""
COHORT_TIMECREATED="0"
MEMBER_COUNT="0"
MEMBERS_JSON="[]"

if [ -n "$COHORT_DATA" ]; then
    COHORT_FOUND="true"
    COHORT_ID=$(echo "$COHORT_DATA" | cut -f1 | tr -d '[:space:]')
    COHORT_NAME=$(echo "$COHORT_DATA" | cut -f2)
    COHORT_IDNUMBER=$(echo "$COHORT_DATA" | cut -f3)
    COHORT_TIMECREATED=$(echo "$COHORT_DATA" | cut -f4 | tr -d '[:space:]')
    
    # Check members
    MEMBER_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_cohort_members WHERE cohortid=$COHORT_ID" | tr -d '[:space:]')
    
    # Get list of usernames in cohort
    MEMBERS_LIST=$(moodle_query "
        SELECT u.username 
        FROM mdl_cohort_members cm 
        JOIN mdl_user u ON cm.userid = u.id 
        WHERE cm.cohortid=$COHORT_ID
    ")
    
    # Convert newline separated list to JSON array
    MEMBERS_JSON="["
    FIRST=1
    while IFS= read -r member; do
        if [ -n "$member" ]; then
            if [ $FIRST -eq 1 ]; then FIRST=0; else MEMBERS_JSON="$MEMBERS_JSON,"; fi
            MEMBERS_JSON="$MEMBERS_JSON\"$member\""
        fi
    done <<< "$MEMBERS_LIST"
    MEMBERS_JSON="$MEMBERS_JSON]"
    
    echo "Cohort Found: ID=$COHORT_ID, Name='$COHORT_NAME', Members=$MEMBER_COUNT"
fi

# 2. Verify Course Enrollment Method
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')
ENROL_METHOD_FOUND="false"
ENROL_ROLE_ID=""
ENROL_ROLE_ARCHETYPE=""

if [ -n "$COURSE_ID" ] && [ -n "$COHORT_ID" ]; then
    # Check for cohort sync method linked to this cohort
    # mdl_enrol: enrol='cohort', customint1=cohort_id
    ENROL_DATA=$(moodle_query "SELECT id, roleid FROM mdl_enrol WHERE enrol='cohort' AND courseid=$COURSE_ID AND customint1=$COHORT_ID LIMIT 1")
    
    if [ -n "$ENROL_DATA" ]; then
        ENROL_METHOD_FOUND="true"
        ENROL_ROLE_ID=$(echo "$ENROL_DATA" | cut -f2 | tr -d '[:space:]')
        
        # Get role archetype (to confirm it is Student)
        ENROL_ROLE_ARCHETYPE=$(moodle_query "SELECT archetype FROM mdl_role WHERE id=$ENROL_ROLE_ID" | tr -d '[:space:]')
        echo "Enrollment Method Found. Role ID: $ENROL_ROLE_ID ($ENROL_ROLE_ARCHETYPE)"
    fi
fi

# Escape JSON strings
COHORT_NAME_ESC=$(echo "$COHORT_NAME" | sed 's/"/\\"/g')
COHORT_IDNUMBER_ESC=$(echo "$COHORT_IDNUMBER" | sed 's/"/\\"/g')

# Create JSON
TEMP_JSON=$(mktemp /tmp/cohort_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": ${TASK_START:-0},
    "cohort_found": $COHORT_FOUND,
    "cohort_id": "${COHORT_ID}",
    "cohort_name": "${COHORT_NAME_ESC}",
    "cohort_idnumber": "${COHORT_IDNUMBER_ESC}",
    "cohort_timecreated": ${COHORT_TIMECREATED:-0},
    "member_count": ${MEMBER_COUNT:-0},
    "members": $MEMBERS_JSON,
    "course_id": "${COURSE_ID}",
    "enrol_method_found": $ENROL_METHOD_FOUND,
    "enrol_role_archetype": "${ENROL_ROLE_ARCHETYPE}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_cohort_enrollment_result.json

echo ""
cat /tmp/create_cohort_enrollment_result.json
echo ""
echo "=== Export Complete ==="