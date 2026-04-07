#!/bin/bash
# Export script for Configure Blind Marking Assignment task

echo "=== Exporting Blind Marking Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
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

# 1. Check Course Creation
# Look for ETHICS101
COURSE_DATA=$(moodle_query "SELECT id, fullname, shortname, category FROM mdl_course WHERE shortname='ETHICS101' LIMIT 1")

COURSE_FOUND="false"
COURSE_ID=""
COURSE_FULLNAME=""
COURSE_CATEGORY=""

if [ -n "$COURSE_DATA" ]; then
    COURSE_FOUND="true"
    COURSE_ID=$(echo "$COURSE_DATA" | cut -f1 | tr -d '[:space:]')
    COURSE_FULLNAME=$(echo "$COURSE_DATA" | cut -f2)
    COURSE_CATEGORY=$(echo "$COURSE_DATA" | cut -f4 | tr -d '[:space:]')
    echo "Course found: ID=$COURSE_ID, Name=$COURSE_FULLNAME, Cat=$COURSE_CATEGORY"
else
    echo "Course ETHICS101 NOT found"
fi

# 2. Check Assignment Configuration (if course exists)
ASSIGN_FOUND="false"
BLIND_MARKING="0"
MARKING_WORKFLOW="0"
MARKING_ALLOCATION="0"
FILE_TYPES=""
ASSIGN_ID=""
ASSIGN_NAME=""

if [ -n "$COURSE_ID" ]; then
    # Look for assignment in this specific course
    ASSIGN_DATA=$(moodle_query "SELECT id, name, blindmarking, markingworkflow, markingallocation, filetypeslist FROM mdl_assign WHERE course=$COURSE_ID AND name='Final Capstone Paper' LIMIT 1")
    
    if [ -n "$ASSIGN_DATA" ]; then
        ASSIGN_FOUND="true"
        ASSIGN_ID=$(echo "$ASSIGN_DATA" | cut -f1 | tr -d '[:space:]')
        ASSIGN_NAME=$(echo "$ASSIGN_DATA" | cut -f2)
        BLIND_MARKING=$(echo "$ASSIGN_DATA" | cut -f3 | tr -d '[:space:]')
        MARKING_WORKFLOW=$(echo "$ASSIGN_DATA" | cut -f4 | tr -d '[:space:]')
        MARKING_ALLOCATION=$(echo "$ASSIGN_DATA" | cut -f5 | tr -d '[:space:]')
        FILE_TYPES=$(echo "$ASSIGN_DATA" | cut -f6)
        
        echo "Assignment found: ID=$ASSIGN_ID"
        echo "Config: Blind=$BLIND_MARKING, Workflow=$MARKING_WORKFLOW, Allocation=$MARKING_ALLOCATION, Types=$FILE_TYPES"
    else
        echo "Assignment 'Final Capstone Paper' NOT found in course $COURSE_ID"
    fi
fi

# 3. Check Category Name (if course exists)
CATEGORY_NAME=""
if [ -n "$COURSE_CATEGORY" ]; then
    CATEGORY_NAME=$(moodle_query "SELECT name FROM mdl_course_categories WHERE id=$COURSE_CATEGORY" | head -1)
fi

# 4. Check timestamps (Anti-gaming)
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
COURSE_CREATED_DURING_TASK="false"
ASSIGN_MODIFIED_DURING_TASK="false"

if [ -n "$COURSE_ID" ]; then
    COURSE_TIMECREATED=$(moodle_query "SELECT timecreated FROM mdl_course WHERE id=$COURSE_ID" | tr -d '[:space:]')
    if [ "$COURSE_TIMECREATED" -ge "$TASK_START_TIME" ]; then
        COURSE_CREATED_DURING_TASK="true"
    fi
fi

if [ -n "$ASSIGN_ID" ]; then
    ASSIGN_TIMEMODIFIED=$(moodle_query "SELECT timemodified FROM mdl_assign WHERE id=$ASSIGN_ID" | tr -d '[:space:]')
    if [ "$ASSIGN_TIMEMODIFIED" -ge "$TASK_START_TIME" ]; then
        ASSIGN_MODIFIED_DURING_TASK="true"
    fi
fi

# Create result JSON
# Escape strings for JSON
COURSE_FULLNAME_ESC=$(echo "$COURSE_FULLNAME" | sed 's/"/\\"/g')
CATEGORY_NAME_ESC=$(echo "$CATEGORY_NAME" | sed 's/"/\\"/g')
FILE_TYPES_ESC=$(echo "$FILE_TYPES" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/blind_marking_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_found": $COURSE_FOUND,
    "course_id": "${COURSE_ID}",
    "course_fullname": "${COURSE_FULLNAME_ESC}",
    "category_name": "${CATEGORY_NAME_ESC}",
    "course_created_during_task": $COURSE_CREATED_DURING_TASK,
    "assign_found": $ASSIGN_FOUND,
    "assign_id": "${ASSIGN_ID}",
    "blind_marking": ${BLIND_MARKING:-0},
    "marking_workflow": ${MARKING_WORKFLOW:-0},
    "marking_allocation": ${MARKING_ALLOCATION:-0},
    "file_types": "${FILE_TYPES_ESC}",
    "assign_modified_during_task": $ASSIGN_MODIFIED_DURING_TASK,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_blind_marking_assignment_result.json

echo ""
cat /tmp/configure_blind_marking_assignment_result.json
echo ""
echo "=== Export Complete ==="