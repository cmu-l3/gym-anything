#!/bin/bash
# Export script for Configure Quiz Overrides task

echo "=== Exporting Configure Quiz Overrides Result ==="

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

# Load stored IDs
QUIZ_ID=$(cat /tmp/quiz_id.txt 2>/dev/null || echo "0")
USER_ID=$(cat /tmp/user_id.txt 2>/dev/null || echo "0")
GROUP_ID=$(cat /tmp/group_id.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_override_count 2>/dev/null || echo "0")

echo "Quiz: $QUIZ_ID, User: $USER_ID, Group: $GROUP_ID"

# Get Current Override Count
CURRENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_overrides WHERE quiz=$QUIZ_ID" | tr -d '[:space:]')
CURRENT_COUNT=${CURRENT_COUNT:-0}

# Get User Override Details
# Query for override specific to epatel on this quiz
USER_OVERRIDE_DATA=$(moodle_query "SELECT id, timelimit, attempts FROM mdl_quiz_overrides WHERE quiz=$QUIZ_ID AND userid=$USER_ID AND groupid IS NULL LIMIT 1")

USER_OVERRIDE_FOUND="false"
USER_TIMELIMIT="0"
USER_ATTEMPTS="0"

if [ -n "$USER_OVERRIDE_DATA" ]; then
    USER_OVERRIDE_FOUND="true"
    USER_TIMELIMIT=$(echo "$USER_OVERRIDE_DATA" | cut -f2 | tr -d '[:space:]')
    USER_ATTEMPTS=$(echo "$USER_OVERRIDE_DATA" | cut -f3 | tr -d '[:space:]')
    echo "User Override: Found (Time: $USER_TIMELIMIT, Attempts: $USER_ATTEMPTS)"
else
    echo "User Override: Not Found"
fi

# Get Group Override Details
# Query for override specific to Extended Time Group on this quiz
GROUP_OVERRIDE_DATA=$(moodle_query "SELECT id, timelimit, attempts FROM mdl_quiz_overrides WHERE quiz=$QUIZ_ID AND groupid=$GROUP_ID AND userid IS NULL LIMIT 1")

GROUP_OVERRIDE_FOUND="false"
GROUP_TIMELIMIT="0"
GROUP_ATTEMPTS="0"

if [ -n "$GROUP_OVERRIDE_DATA" ]; then
    GROUP_OVERRIDE_FOUND="true"
    GROUP_TIMELIMIT=$(echo "$GROUP_OVERRIDE_DATA" | cut -f2 | tr -d '[:space:]')
    GROUP_ATTEMPTS=$(echo "$GROUP_OVERRIDE_DATA" | cut -f3 | tr -d '[:space:]')
    echo "Group Override: Found (Time: $GROUP_TIMELIMIT, Attempts: $GROUP_ATTEMPTS)"
else
    echo "Group Override: Not Found"
fi

# Verify Quiz still exists and has base settings (just sanity check)
QUIZ_BASE=$(moodle_query "SELECT timelimit, attempts FROM mdl_quiz WHERE id=$QUIZ_ID")
echo "Quiz Base Settings: $QUIZ_BASE"

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/overrides_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "quiz_id": ${QUIZ_ID:-0},
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "user_override": {
        "found": $USER_OVERRIDE_FOUND,
        "timelimit": ${USER_TIMELIMIT:-0},
        "attempts": ${USER_ATTEMPTS:-0}
    },
    "group_override": {
        "found": $GROUP_OVERRIDE_FOUND,
        "timelimit": ${GROUP_TIMELIMIT:-0},
        "attempts": ${GROUP_ATTEMPTS:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_quiz_overrides_result.json

echo ""
cat /tmp/configure_quiz_overrides_result.json
echo ""
echo "=== Export Complete ==="