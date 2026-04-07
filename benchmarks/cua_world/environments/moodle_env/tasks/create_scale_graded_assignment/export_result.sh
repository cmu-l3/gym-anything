#!/bin/bash
# Export script for Create Scale Graded Assignment task

echo "=== Exporting Create Scale Graded Assignment Result ==="

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

# Retrieve stored IDs and counts
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_SCALE_COUNT=$(cat /tmp/initial_scale_count 2>/dev/null || echo "0")
INITIAL_ASSIGN_COUNT=$(cat /tmp/initial_assign_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_SCALE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_scale" | tr -d '[:space:]')
CURRENT_ASSIGN_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_assign WHERE course=$COURSE_ID" | tr -d '[:space:]')

echo "Scales: $INITIAL_SCALE_COUNT -> $CURRENT_SCALE_COUNT"
echo "Assignments: $INITIAL_ASSIGN_COUNT -> $CURRENT_ASSIGN_COUNT"

# --- CHECK SCALE ---
# Look for the specific scale
SCALE_DATA=$(moodle_query "SELECT id, name, scale FROM mdl_scale WHERE LOWER(name) LIKE '%clinical competency scale%' ORDER BY id DESC LIMIT 1")

SCALE_FOUND="false"
SCALE_ID=""
SCALE_NAME=""
SCALE_VALUES=""

if [ -n "$SCALE_DATA" ]; then
    SCALE_FOUND="true"
    SCALE_ID=$(echo "$SCALE_DATA" | cut -f1 | tr -d '[:space:]')
    SCALE_NAME=$(echo "$SCALE_DATA" | cut -f2)
    SCALE_VALUES=$(echo "$SCALE_DATA" | cut -f3)
    echo "Scale found: ID=$SCALE_ID, Name='$SCALE_NAME'"
else
    echo "Scale 'Clinical Competency Scale' NOT found"
fi

# --- CHECK ASSIGNMENT ---
# Look for the assignment in the correct course
ASSIGN_DATA=$(moodle_query "SELECT id, name, grade FROM mdl_assign WHERE course=$COURSE_ID AND LOWER(name) LIKE '%lab skills assessment%' ORDER BY id DESC LIMIT 1")

ASSIGN_FOUND="false"
ASSIGN_ID=""
ASSIGN_NAME=""
ASSIGN_GRADE="0"

if [ -n "$ASSIGN_DATA" ]; then
    ASSIGN_FOUND="true"
    ASSIGN_ID=$(echo "$ASSIGN_DATA" | cut -f1 | tr -d '[:space:]')
    ASSIGN_NAME=$(echo "$ASSIGN_DATA" | cut -f2)
    ASSIGN_GRADE=$(echo "$ASSIGN_DATA" | cut -f3 | tr -d '[:space:]')
    echo "Assignment found: ID=$ASSIGN_ID, Name='$ASSIGN_NAME', Grade=$ASSIGN_GRADE"
else
    echo "Assignment 'Lab Skills Assessment' NOT found in course $COURSE_ID"
fi

# Calculate scale usage
# In Moodle, if 'grade' < 0, it indicates a scale is used.
# The Scale ID is ABS(grade).
ASSIGN_USES_SCALE="false"
ASSIGN_SCALE_ID="0"

if [ "$ASSIGN_FOUND" = "true" ]; then
    if [ "$ASSIGN_GRADE" -lt 0 ]; then
        ASSIGN_USES_SCALE="true"
        ASSIGN_SCALE_ID=$((ASSIGN_GRADE * -1))
        echo "Assignment uses scale ID: $ASSIGN_SCALE_ID"
    else
        echo "Assignment uses point grading (Grade=$ASSIGN_GRADE)"
    fi
fi

# Escape JSON strings
SCALE_NAME_ESC=$(echo "$SCALE_NAME" | sed 's/"/\\"/g')
SCALE_VALUES_ESC=$(echo "$SCALE_VALUES" | sed 's/"/\\"/g')
ASSIGN_NAME_ESC=$(echo "$ASSIGN_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/scale_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_scale_count": ${INITIAL_SCALE_COUNT:-0},
    "current_scale_count": ${CURRENT_SCALE_COUNT:-0},
    "initial_assign_count": ${INITIAL_ASSIGN_COUNT:-0},
    "current_assign_count": ${CURRENT_ASSIGN_COUNT:-0},
    "scale_found": $SCALE_FOUND,
    "scale_id": "${SCALE_ID:-0}",
    "scale_name": "$SCALE_NAME_ESC",
    "scale_values": "$SCALE_VALUES_ESC",
    "assign_found": $ASSIGN_FOUND,
    "assign_id": "${ASSIGN_ID:-0}",
    "assign_name": "$ASSIGN_NAME_ESC",
    "assign_grade_raw": ${ASSIGN_GRADE:-0},
    "assign_uses_scale": $ASSIGN_USES_SCALE,
    "assign_scale_id": "${ASSIGN_SCALE_ID:-0}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_scale_graded_assignment_result.json

echo ""
cat /tmp/create_scale_graded_assignment_result.json
echo ""
echo "=== Export Complete ==="