#!/bin/bash
# Export script for Upload SCORM task

echo "=== Exporting Upload SCORM Result ==="

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

# Get Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='FIRE101'" | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    echo "ERROR: Course FIRE101 not found during export!"
    COURSE_ID=0
fi

# Get task timing
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_scorm_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_scorm WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_COUNT=${CURRENT_COUNT:-0}

echo "SCORM count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Find the target activity
# We look for the most recently created SCORM activity in this course
SCORM_DATA=$(moodle_query "SELECT id, name, reference, grademethod, maxgrade, maxattempt, timemodified FROM mdl_scorm WHERE course=$COURSE_ID ORDER BY id DESC LIMIT 1")

FOUND="false"
ID=""
NAME=""
REFERENCE=""
GRADEMETHOD=""
MAXGRADE=""
MAXATTEMPT=""
TIMEMODIFIED="0"

if [ -n "$SCORM_DATA" ]; then
    FOUND="true"
    ID=$(echo "$SCORM_DATA" | cut -f1 | tr -d '[:space:]')
    NAME=$(echo "$SCORM_DATA" | cut -f2)
    REFERENCE=$(echo "$SCORM_DATA" | cut -f3)
    GRADEMETHOD=$(echo "$SCORM_DATA" | cut -f4 | tr -d '[:space:]')
    MAXGRADE=$(echo "$SCORM_DATA" | cut -f5 | tr -d '[:space:]')
    MAXATTEMPT=$(echo "$SCORM_DATA" | cut -f6 | tr -d '[:space:]')
    TIMEMODIFIED=$(echo "$SCORM_DATA" | cut -f7 | tr -d '[:space:]')

    echo "Found SCORM: ID=$ID, Name='$NAME', File='$REFERENCE'"
    echo "Settings: GradeMethod=$GRADEMETHOD, MaxGrade=$MAXGRADE, Attempts=$MAXATTEMPT"
else
    echo "No SCORM activity found in FIRE101"
fi

# Check if file was uploaded (reference should not be empty)
FILE_UPLOADED="false"
if [ -n "$REFERENCE" ] && [ "$REFERENCE" != "NULL" ]; then
    FILE_UPLOADED="true"
fi

# Escape JSON strings
NAME_ESC=$(echo "$NAME" | sed 's/"/\\"/g')
REFERENCE_ESC=$(echo "$REFERENCE" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/scorm_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": $COURSE_ID,
    "task_start_timestamp": $TASK_START,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "scorm_found": $FOUND,
    "activity": {
        "id": "$ID",
        "name": "$NAME_ESC",
        "reference": "$REFERENCE_ESC",
        "grademethod": ${GRADEMETHOD:-0},
        "maxgrade": ${MAXGRADE:-0},
        "maxattempt": ${MAXATTEMPT:-0},
        "timemodified": ${TIMEMODIFIED:-0}
    },
    "file_uploaded": $FILE_UPLOADED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/upload_scorm_result.json

echo ""
cat /tmp/upload_scorm_result.json
echo ""
echo "=== Export Complete ==="