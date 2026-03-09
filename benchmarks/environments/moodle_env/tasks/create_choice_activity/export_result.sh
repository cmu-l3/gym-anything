#!/bin/bash
# Export script for Create Choice Activity task

echo "=== Exporting Create Choice Activity Result ==="

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

# Get CS110 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CS110'" | tr -d '[:space:]')

# Get baseline
INITIAL_CHOICE_COUNT=$(cat /tmp/initial_choice_count 2>/dev/null || echo "0")

# Get current choice activity count
CURRENT_CHOICE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_choice WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_CHOICE_COUNT=${CURRENT_CHOICE_COUNT:-0}

echo "Choice count: initial=$INITIAL_CHOICE_COUNT, current=$CURRENT_CHOICE_COUNT"

# Look for the target choice activity
CHOICE_DATA=$(moodle_query "SELECT id, name, allowupdate, showresults FROM mdl_choice WHERE course=$COURSE_ID AND LOWER(name) LIKE '%preferred programming language%' ORDER BY id DESC LIMIT 1")

CHOICE_FOUND="false"
CHOICE_ID=""
CHOICE_NAME=""
CHOICE_ALLOWUPDATE="0"
CHOICE_SHOWRESULTS="0"
OPTION_COUNT="0"
HAS_PYTHON="false"
HAS_JAVA="false"
HAS_CPP="false"
HAS_JAVASCRIPT="false"

if [ -n "$CHOICE_DATA" ]; then
    CHOICE_FOUND="true"
    CHOICE_ID=$(echo "$CHOICE_DATA" | cut -f1 | tr -d '[:space:]')
    CHOICE_NAME=$(echo "$CHOICE_DATA" | cut -f2)
    CHOICE_ALLOWUPDATE=$(echo "$CHOICE_DATA" | cut -f3 | tr -d '[:space:]')
    CHOICE_SHOWRESULTS=$(echo "$CHOICE_DATA" | cut -f4 | tr -d '[:space:]')

    # Count and check options
    OPTION_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_choice_options WHERE choiceid=$CHOICE_ID" | tr -d '[:space:]')

    # Check each expected option
    OPTIONS_DATA=$(moodle_query "SELECT text FROM mdl_choice_options WHERE choiceid=$CHOICE_ID")
    OPTIONS_LOWER=$(echo "$OPTIONS_DATA" | tr '[:upper:]' '[:lower:]')
    echo "$OPTIONS_LOWER" | grep -qi "python" && HAS_PYTHON="true"
    echo "$OPTIONS_LOWER" | grep -qi "java\b\|^java$\|java " && HAS_JAVA="true"
    # Also check for exact "java" without javascript
    JAVA_EXACT=$(moodle_query "SELECT COUNT(*) FROM mdl_choice_options WHERE choiceid=$CHOICE_ID AND LOWER(TRIM(text))='java'" | tr -d '[:space:]')
    [ "$JAVA_EXACT" -gt 0 ] 2>/dev/null && HAS_JAVA="true"
    echo "$OPTIONS_LOWER" | grep -qi "c++" && HAS_CPP="true"
    echo "$OPTIONS_LOWER" | grep -qi "javascript" && HAS_JAVASCRIPT="true"

    echo "Choice found: ID=$CHOICE_ID, Name='$CHOICE_NAME', AllowUpdate=$CHOICE_ALLOWUPDATE, ShowResults=$CHOICE_SHOWRESULTS"
    echo "Options ($OPTION_COUNT): Python=$HAS_PYTHON, Java=$HAS_JAVA, C++=$HAS_CPP, JavaScript=$HAS_JAVASCRIPT"
else
    echo "Target choice activity NOT found in CS110"
fi

# Verify choice is in correct course
CHOICE_COURSE_ID=""
if [ -n "$CHOICE_ID" ]; then
    CHOICE_COURSE_ID=$(moodle_query "SELECT course FROM mdl_choice WHERE id=$CHOICE_ID" | tr -d '[:space:]')
fi

# Escape for JSON
CHOICE_NAME_ESC=$(echo "$CHOICE_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/choice_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_choice_count": ${INITIAL_CHOICE_COUNT:-0},
    "current_choice_count": ${CURRENT_CHOICE_COUNT:-0},
    "choice_found": $CHOICE_FOUND,
    "choice_id": "$CHOICE_ID",
    "choice_name": "$CHOICE_NAME_ESC",
    "choice_course_id": "$CHOICE_COURSE_ID",
    "choice_allowupdate": ${CHOICE_ALLOWUPDATE:-0},
    "choice_showresults": ${CHOICE_SHOWRESULTS:-0},
    "option_count": ${OPTION_COUNT:-0},
    "has_python": $HAS_PYTHON,
    "has_java": $HAS_JAVA,
    "has_cpp": $HAS_CPP,
    "has_javascript": $HAS_JAVASCRIPT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_choice_activity_result.json

echo ""
cat /tmp/create_choice_activity_result.json
echo ""
echo "=== Export Complete ==="
