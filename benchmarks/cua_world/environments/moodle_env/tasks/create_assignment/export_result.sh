#!/bin/bash
# Export script for Create Assignment task

echo "=== Exporting Create Assignment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Read stored values
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_ASSIGNMENT_COUNT=$(cat /tmp/initial_assignment_count 2>/dev/null || echo "0")

# Get current assignment count
CURRENT_ASSIGNMENT_COUNT="0"
if [ "$COURSE_ID" != "0" ]; then
    CURRENT_ASSIGNMENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_assign WHERE course=$COURSE_ID" 2>/dev/null || echo "0")
fi

echo "Assignment count: initial=$INITIAL_ASSIGNMENT_COUNT, current=$CURRENT_ASSIGNMENT_COUNT"

# Debug: Show assignments in the course
echo ""
echo "=== DEBUG: Assignments in BIO101 ==="
moodle_query_headers "SELECT id, name, course, duedate FROM mdl_assign WHERE course=$COURSE_ID ORDER BY id DESC LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# Check for the target assignment - EXACT match only, no fallbacks
echo "Searching for assignment 'Lab Report: Cell Biology' (exact match, case-insensitive)..."
ASSIGN_DATA=$(moodle_query "SELECT a.id, a.name, a.course, a.duedate, a.intro FROM mdl_assign a WHERE LOWER(TRIM(a.name))=LOWER(TRIM('Lab Report: Cell Biology')) AND a.course=$COURSE_ID ORDER BY a.id DESC LIMIT 1" 2>/dev/null)

# NO FALLBACKS - only exact name match allowed
# The verifier requires exact matching - partial matches would give false positives
if [ -z "$ASSIGN_DATA" ]; then
    echo "Assignment 'Lab Report: Cell Biology' NOT found in database."
    echo "No fallback queries - only exact name match accepted."
fi

# Parse assignment data
ASSIGN_FOUND="false"
ASSIGN_ID=""
ASSIGN_NAME=""
ASSIGN_DUEDATE=""
ASSIGN_HAS_DESCRIPTION="false"

if [ -n "$ASSIGN_DATA" ]; then
    ASSIGN_FOUND="true"
    ASSIGN_ID=$(echo "$ASSIGN_DATA" | cut -f1)
    ASSIGN_NAME=$(echo "$ASSIGN_DATA" | cut -f2)
    ASSIGN_DUEDATE=$(echo "$ASSIGN_DATA" | cut -f4)
    ASSIGN_INTRO=$(echo "$ASSIGN_DATA" | cut -f5)

    # Check if description is non-empty
    if [ -n "$ASSIGN_INTRO" ] && [ "$ASSIGN_INTRO" != "NULL" ]; then
        ASSIGN_HAS_DESCRIPTION="true"
    fi

    echo "Assignment found: ID=$ASSIGN_ID, Name='$ASSIGN_NAME', Due=$ASSIGN_DUEDATE"
else
    echo "Assignment 'Lab Report: Cell Biology' NOT found"
fi

# Check submission type (online text)
SUBMISSION_TYPE=""
HAS_ONLINETEXT="false"
if [ -n "$ASSIGN_ID" ]; then
    # Check if onlinetext submission is enabled
    ONLINETEXT_ENABLED=$(moodle_query "SELECT value FROM mdl_assign_plugin_config WHERE assignment=$ASSIGN_ID AND plugin='onlinetext' AND subtype='assignsubmission' AND name='enabled'" 2>/dev/null)
    if [ "$ONLINETEXT_ENABLED" = "1" ]; then
        HAS_ONLINETEXT="true"
        SUBMISSION_TYPE="onlinetext"
    fi

    # Also check file submission
    FILE_ENABLED=$(moodle_query "SELECT value FROM mdl_assign_plugin_config WHERE assignment=$ASSIGN_ID AND plugin='file' AND subtype='assignsubmission' AND name='enabled'" 2>/dev/null)
    if [ "$FILE_ENABLED" = "1" ]; then
        if [ -n "$SUBMISSION_TYPE" ]; then
            SUBMISSION_TYPE="${SUBMISSION_TYPE},file"
        else
            SUBMISSION_TYPE="file"
        fi
    fi
fi

# Escape special characters for JSON
ASSIGN_NAME_ESC=$(echo "$ASSIGN_NAME" | sed 's/"/\\"/g')
SUBMISSION_TYPE_ESC=$(echo "$SUBMISSION_TYPE" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/create_assignment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": $COURSE_ID,
    "initial_assignment_count": ${INITIAL_ASSIGNMENT_COUNT:-0},
    "current_assignment_count": ${CURRENT_ASSIGNMENT_COUNT:-0},
    "assignment_found": $ASSIGN_FOUND,
    "assignment": {
        "id": "$ASSIGN_ID",
        "name": "$ASSIGN_NAME_ESC",
        "duedate": "$ASSIGN_DUEDATE",
        "has_description": $ASSIGN_HAS_DESCRIPTION,
        "submission_type": "$SUBMISSION_TYPE_ESC",
        "has_onlinetext": $HAS_ONLINETEXT
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_assignment_result.json

echo ""
cat /tmp/create_assignment_result.json
echo ""
echo "=== Export Complete ==="
