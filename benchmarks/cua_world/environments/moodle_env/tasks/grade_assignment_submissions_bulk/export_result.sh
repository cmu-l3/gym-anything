#!/bin/bash
# Export script for Grade Assignment Submissions task

echo "=== Exporting Grading Results ==="

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
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Fetch data for the specific assignment and students
# We query the grade and the feedback comment
# Schema info:
# mdl_assign: name='Lab 3: Titration Analysis' -> id
# mdl_user: username -> id
# mdl_assign_grades: assignment=assign.id, userid=user.id -> grade, grader, timemodified, id
# mdl_assignfeedback_comments: grade=assign_grades.id -> commenttext

# Get Assignment ID
ASSIGN_ID=$(moodle_query "SELECT id FROM mdl_assign WHERE name='Lab 3: Titration Analysis' LIMIT 1")
echo "Assignment ID: $ASSIGN_ID"

# Get Grader ID (teacher1)
GRADER_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='teacher1'")
echo "Grader ID (teacher1): $GRADER_ID"

# Function to get student data JSON
get_student_json() {
    local username="$1"
    local uid=$(moodle_query "SELECT id FROM mdl_user WHERE username='$username'")
    
    if [ -z "$uid" ]; then
        echo "null"
        return
    fi

    # Get grade record
    local grade_data=$(moodle_query "SELECT id, grade, grader, timemodified FROM mdl_assign_grades WHERE assignment=$ASSIGN_ID AND userid=$uid")
    
    if [ -z "$grade_data" ]; then
        echo "{\"username\": \"$username\", \"found\": false}"
        return
    fi
    
    local gid=$(echo "$grade_data" | cut -f1)
    local grade=$(echo "$grade_data" | cut -f2)
    local grader=$(echo "$grade_data" | cut -f3)
    local time=$(echo "$grade_data" | cut -f4)
    
    # Get feedback
    # Note: mdl_assignfeedback_comments links to assignment and grade. 
    # The 'grade' column in comments table is the 'id' from assign_grades table.
    local feedback=$(moodle_query "SELECT commenttext FROM mdl_assignfeedback_comments WHERE grade=$gid")
    
    # Escape for JSON
    local fb_esc=$(echo "$feedback" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
    
    echo "{
        \"username\": \"$username\",
        \"found\": true,
        \"grade\": \"$grade\",
        \"grader_id\": \"$grader\",
        \"timemodified\": $time,
        \"feedback\": \"$fb_esc\"
    }"
}

echo "Fetching student data..."
JSMITH_JSON=$(get_student_json "jsmith")
MJONES_JSON=$(get_student_json "mjones")
AWILSON_JSON=$(get_student_json "awilson")

# Construct full JSON
TEMP_JSON=$(mktemp /tmp/grading_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "assignment_id": "${ASSIGN_ID}",
    "expected_grader_id": "${GRADER_ID}",
    "students": {
        "jsmith": $JSMITH_JSON,
        "mjones": $MJONES_JSON,
        "awilson": $AWILSON_JSON
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/grading_result.json
rm -f "$TEMP_JSON"

echo ""
cat /tmp/grading_result.json
echo ""
echo "=== Export Complete ==="