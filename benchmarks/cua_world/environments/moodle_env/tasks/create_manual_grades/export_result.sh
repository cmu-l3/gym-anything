#!/bin/bash
# Export script for Create Manual Grades task

echo "=== Exporting Create Manual Grades Result ==="

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

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
COURSE_ID=${COURSE_ID:-0}

# Get baselines
INITIAL_ITEM_COUNT=$(cat /tmp/initial_item_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current item count
CURRENT_ITEM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemtype='manual'" | tr -d '[:space:]')
CURRENT_ITEM_COUNT=${CURRENT_ITEM_COUNT:-0}

echo "Manual grade items: initial=$INITIAL_ITEM_COUNT, current=$CURRENT_ITEM_COUNT"

# Find the specific grade item
# Looking for "Clinical Skills Assessment" (manual type)
ITEM_DATA=$(moodle_query "SELECT id, itemname, grademax, gradepass, timecreated FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemtype='manual' AND LOWER(itemname) LIKE '%clinical skills assessment%' ORDER BY id DESC LIMIT 1")

ITEM_FOUND="false"
ITEM_ID=""
ITEM_NAME=""
GRADE_MAX="0"
GRADE_PASS="0"
TIME_CREATED="0"

GRADES_JSON="{}"

if [ -n "$ITEM_DATA" ]; then
    ITEM_FOUND="true"
    ITEM_ID=$(echo "$ITEM_DATA" | cut -f1 | tr -d '[:space:]')
    ITEM_NAME=$(echo "$ITEM_DATA" | cut -f2)
    GRADE_MAX=$(echo "$ITEM_DATA" | cut -f3 | tr -d '[:space:]')
    GRADE_PASS=$(echo "$ITEM_DATA" | cut -f4 | tr -d '[:space:]')
    TIME_CREATED=$(echo "$ITEM_DATA" | cut -f5 | tr -d '[:space:]')

    echo "Item found: ID=$ITEM_ID, Name='$ITEM_NAME', Max=$GRADE_MAX, Pass=$GRADE_PASS"

    # Get student grades
    # jsmith, mjones, awilson, bbrown
    # Construct JSON object for grades: {"jsmith": 45.0, "mjones": 32.0, ...}
    
    GRADES_JSON_PARTS=""
    STUDENTS=("jsmith" "mjones" "awilson" "bbrown")
    
    for USERNAME in "${STUDENTS[@]}"; do
        USER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='$USERNAME'" | tr -d '[:space:]')
        if [ -n "$USER_ID" ]; then
            # Get finalgrade
            GRADE_VAL=$(moodle_query "SELECT finalgrade FROM mdl_grade_grades WHERE itemid=$ITEM_ID AND userid=$USER_ID" | tr -d '[:space:]')
            
            # If grade is NULL/empty, set to null in JSON
            if [ -z "$GRADE_VAL" ] || [ "$GRADE_VAL" = "NULL" ]; then
                GRADE_VAL="null"
            fi
            
            if [ -n "$GRADES_JSON_PARTS" ]; then
                GRADES_JSON_PARTS="$GRADES_JSON_PARTS, \"$USERNAME\": $GRADE_VAL"
            else
                GRADES_JSON_PARTS="\"$USERNAME\": $GRADE_VAL"
            fi
        fi
    done
    GRADES_JSON="{ $GRADES_JSON_PARTS }"
    echo "Grades found: $GRADES_JSON"

else
    echo "Grade item 'Clinical Skills Assessment' NOT found"
fi

# Escape name for JSON
ITEM_NAME_ESC=$(echo "$ITEM_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/manual_grades_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": $COURSE_ID,
    "initial_item_count": $INITIAL_ITEM_COUNT,
    "current_item_count": $CURRENT_ITEM_COUNT,
    "item_found": $ITEM_FOUND,
    "item_id": "$ITEM_ID",
    "item_name": "$ITEM_NAME_ESC",
    "grade_max": ${GRADE_MAX:-0},
    "grade_pass": ${GRADE_PASS:-0},
    "time_created": ${TIME_CREATED:-0},
    "task_start_time": $TASK_START,
    "student_grades": $GRADES_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_manual_grades_result.json

echo ""
cat /tmp/create_manual_grades_result.json
echo ""
echo "=== Export Complete ==="