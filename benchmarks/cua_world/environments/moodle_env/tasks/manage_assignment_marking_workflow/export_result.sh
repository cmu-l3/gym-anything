#!/bin/bash
# Export script for Manage Assignment Marking Workflow task

echo "=== Exporting Manage Assignment Marking Workflow Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
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
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Course ID for HIST201
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='HIST201'" | tr -d '[:space:]')
echo "Course ID: $COURSE_ID"

# 2. Get Assignment Info (ID and markingworkflow status)
ASSIGN_DATA=$(moodle_query "SELECT id, markingworkflow FROM mdl_assign WHERE course=$COURSE_ID AND name='Final Research Paper' LIMIT 1")

ASSIGN_FOUND="false"
ASSIGN_ID=""
WORKFLOW_ENABLED="0"

if [ -n "$ASSIGN_DATA" ]; then
    ASSIGN_FOUND="true"
    ASSIGN_ID=$(echo "$ASSIGN_DATA" | cut -f1 | tr -d '[:space:]')
    WORKFLOW_ENABLED=$(echo "$ASSIGN_DATA" | cut -f2 | tr -d '[:space:]')
    echo "Assignment found: ID=$ASSIGN_ID, WorkflowEnabled=$WORKFLOW_ENABLED"
else
    echo "Assignment 'Final Research Paper' NOT found"
fi

# 3. Get Student User ID (bbrown)
USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='bbrown'" | tr -d '[:space:]')
echo "Student ID: $USER_ID"

# 4. Get Student's Grade Workflow State
WORKFLOW_STATE=""
if [ -n "$ASSIGN_ID" ] && [ -n "$USER_ID" ]; then
    # Check mdl_assign_grades
    WORKFLOW_STATE=$(moodle_query "SELECT workflowstate FROM mdl_assign_grades WHERE assignment=$ASSIGN_ID AND userid=$USER_ID" | tr -d '[:space:]')
    
    # If no grade record exists yet, it returns empty
    if [ -z "$WORKFLOW_STATE" ]; then
        WORKFLOW_STATE="notgraded"
    fi
    echo "Student workflow state: $WORKFLOW_STATE"
fi

# 5. Timestamp check (modified time of the assignment)
ASSIGN_TIMEMODIFIED="0"
if [ -n "$ASSIGN_ID" ]; then
    ASSIGN_TIMEMODIFIED=$(moodle_query "SELECT timemodified FROM mdl_assign WHERE id=$ASSIGN_ID" | tr -d '[:space:]')
fi
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/workflow_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_found": $([ -n "$COURSE_ID" ] && echo "true" || echo "false"),
    "assignment_found": $ASSIGN_FOUND,
    "assignment_id": "$ASSIGN_ID",
    "marking_workflow_enabled": $WORKFLOW_ENABLED,
    "student_found": $([ -n "$USER_ID" ] && echo "true" || echo "false"),
    "student_workflow_state": "$WORKFLOW_STATE",
    "assign_timemodified": ${ASSIGN_TIMEMODIFIED:-0},
    "task_start_time": ${TASK_START_TIME:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/manage_assignment_marking_workflow_result.json

echo ""
cat /tmp/manage_assignment_marking_workflow_result.json
echo ""
echo "=== Export Complete ==="