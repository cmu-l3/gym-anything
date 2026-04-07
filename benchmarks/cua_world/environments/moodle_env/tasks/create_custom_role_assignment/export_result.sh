#!/bin/bash
# Export script for Create Custom Role Assignment task

echo "=== Exporting Custom Role Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load target IDs
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
USER_ID=$(cat /tmp/target_user_id 2>/dev/null || echo "0")
INITIAL_MAX_ROLE_ID=$(cat /tmp/initial_max_role_id 2>/dev/null || echo "0")

# 1. Check for Role Existence
echo "Checking for role 'courseauditor'..."
ROLE_DATA=$(moodle_query "SELECT id, name, shortname, description FROM mdl_role WHERE shortname='courseauditor'")

ROLE_FOUND="false"
ROLE_ID="0"
ROLE_NAME=""
ROLE_SHORTNAME=""

if [ -n "$ROLE_DATA" ]; then
    ROLE_FOUND="true"
    ROLE_ID=$(echo "$ROLE_DATA" | cut -f1)
    ROLE_NAME=$(echo "$ROLE_DATA" | cut -f2)
    ROLE_SHORTNAME=$(echo "$ROLE_DATA" | cut -f3)
    echo "Role found: $ROLE_NAME ($ROLE_SHORTNAME) ID=$ROLE_ID"
else
    echo "Role 'courseauditor' NOT found."
fi

# 2. Check Context Levels (Where can this role be assigned?)
# contextlevel 50 = COURSE
ROLE_CONTEXT_COURSE="false"
if [ "$ROLE_FOUND" = "true" ]; then
    CONTEXT_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_role_context_levels WHERE roleid=$ROLE_ID AND contextlevel=50")
    if [ "$CONTEXT_CHECK" -gt 0 ]; then
        ROLE_CONTEXT_COURSE="true"
        echo "Role is assignable in Course context."
    else
        echo "Role is NOT assignable in Course context."
    fi
fi

# 3. Check Capabilities
# 1 = Allow, -1 = Prevent, -1000 = Prohibit, 0/missing = Inherit/Not Set
CAP_COURSE_VIEW="0"
CAP_GRADE_VIEW="0"
CAP_PARTICIPANTS_VIEW="0"

if [ "$ROLE_FOUND" = "true" ]; then
    # moodle/course:view
    RES=$(moodle_query "SELECT permission FROM mdl_role_capabilities WHERE roleid=$ROLE_ID AND capability='moodle/course:view'")
    CAP_COURSE_VIEW=${RES:-0}
    
    # moodle/grade:viewall
    RES=$(moodle_query "SELECT permission FROM mdl_role_capabilities WHERE roleid=$ROLE_ID AND capability='moodle/grade:viewall'")
    CAP_GRADE_VIEW=${RES:-0}
    
    # moodle/course:viewparticipants
    RES=$(moodle_query "SELECT permission FROM mdl_role_capabilities WHERE roleid=$ROLE_ID AND capability='moodle/course:viewparticipants'")
    CAP_PARTICIPANTS_VIEW=${RES:-0}
    
    echo "Capabilities: course:view=$CAP_COURSE_VIEW, grade:viewall=$CAP_GRADE_VIEW, participants:view=$CAP_PARTICIPANTS_VIEW"
fi

# 4. Check Assignment
ASSIGNMENT_FOUND="false"
if [ "$ROLE_FOUND" = "true" ] && [ "$COURSE_ID" != "0" ] && [ "$USER_ID" != "0" ]; then
    # Find the context ID for the course (contextlevel=50)
    COURSE_CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID")
    
    if [ -n "$COURSE_CONTEXT_ID" ]; then
        # Check if user has role in this context
        ASSIGN_CHECK=$(moodle_query "SELECT id FROM mdl_role_assignments WHERE roleid=$ROLE_ID AND contextid=$COURSE_CONTEXT_ID AND userid=$USER_ID")
        if [ -n "$ASSIGN_CHECK" ]; then
            ASSIGNMENT_FOUND="true"
            echo "Role assignment found for user in course."
        else
            echo "Role assignment NOT found."
        fi
    fi
fi

# Escape JSON strings
ROLE_NAME_ESC=$(echo "$ROLE_NAME" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/custom_role_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_max_role_id": ${INITIAL_MAX_ROLE_ID:-0},
    "role_found": $ROLE_FOUND,
    "role": {
        "id": ${ROLE_ID:-0},
        "name": "$ROLE_NAME_ESC",
        "shortname": "$ROLE_SHORTNAME",
        "context_course_enabled": $ROLE_CONTEXT_COURSE,
        "capabilities": {
            "moodle_course_view": ${CAP_COURSE_VIEW:-0},
            "moodle_grade_viewall": ${CAP_GRADE_VIEW:-0},
            "moodle_course_viewparticipants": ${CAP_PARTICIPANTS_VIEW:-0}
        }
    },
    "assignment": {
        "found": $ASSIGNMENT_FOUND,
        "course_id": ${COURSE_ID:-0},
        "user_id": ${USER_ID:-0}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_custom_role_result.json

echo ""
cat /tmp/create_custom_role_result.json
echo ""
echo "=== Export Complete ==="