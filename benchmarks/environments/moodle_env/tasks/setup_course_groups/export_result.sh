#!/bin/bash
# Export script for Setup Course Groups task

echo "=== Exporting Course Groups Result ==="

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

# Get HIST201 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='HIST201'" | tr -d '[:space:]')

# Get baseline
INITIAL_GROUP_COUNT=$(cat /tmp/initial_group_count 2>/dev/null || echo "0")

# Get current group count
CURRENT_GROUP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_groups WHERE courseid=$COURSE_ID" | tr -d '[:space:]')
CURRENT_GROUP_COUNT=${CURRENT_GROUP_COUNT:-0}

echo "Group count: initial=$INITIAL_GROUP_COUNT, current=$CURRENT_GROUP_COUNT"

# --- Look for Discussion Group A ---
GROUP_A_DATA=$(moodle_query "SELECT id, name FROM mdl_groups WHERE courseid=$COURSE_ID AND LOWER(name) LIKE '%discussion group a%' LIMIT 1")
GROUP_A_FOUND="false"
GROUP_A_ID=""
GROUP_A_MEMBER_COUNT="0"
BBROWN_IN_A="false"
CGARCIA_IN_A="false"

if [ -n "$GROUP_A_DATA" ]; then
    GROUP_A_FOUND="true"
    GROUP_A_ID=$(echo "$GROUP_A_DATA" | cut -f1 | tr -d '[:space:]')

    GROUP_A_MEMBER_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_groups_members WHERE groupid=$GROUP_A_ID" | tr -d '[:space:]')

    # Check bbrown
    BBROWN_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='bbrown' AND deleted=0" | tr -d '[:space:]')
    if [ -n "$BBROWN_ID" ]; then
        BBROWN_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_groups_members WHERE groupid=$GROUP_A_ID AND userid=$BBROWN_ID" | tr -d '[:space:]')
        [ "$BBROWN_CHECK" -gt 0 ] 2>/dev/null && BBROWN_IN_A="true"
    fi

    # Check cgarcia
    CGARCIA_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='cgarcia' AND deleted=0" | tr -d '[:space:]')
    if [ -n "$CGARCIA_ID" ]; then
        CGARCIA_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_groups_members WHERE groupid=$GROUP_A_ID AND userid=$CGARCIA_ID" | tr -d '[:space:]')
        [ "$CGARCIA_CHECK" -gt 0 ] 2>/dev/null && CGARCIA_IN_A="true"
    fi

    echo "Group A found: ID=$GROUP_A_ID, Members=$GROUP_A_MEMBER_COUNT, bbrown=$BBROWN_IN_A, cgarcia=$CGARCIA_IN_A"
else
    echo "Discussion Group A NOT found"
fi

# --- Look for Discussion Group B ---
GROUP_B_DATA=$(moodle_query "SELECT id, name FROM mdl_groups WHERE courseid=$COURSE_ID AND LOWER(name) LIKE '%discussion group b%' LIMIT 1")
GROUP_B_FOUND="false"
GROUP_B_ID=""
GROUP_B_MEMBER_COUNT="0"
DLEE_IN_B="false"

if [ -n "$GROUP_B_DATA" ]; then
    GROUP_B_FOUND="true"
    GROUP_B_ID=$(echo "$GROUP_B_DATA" | cut -f1 | tr -d '[:space:]')

    GROUP_B_MEMBER_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_groups_members WHERE groupid=$GROUP_B_ID" | tr -d '[:space:]')

    # Check dlee
    DLEE_ID=$(moodle_query "SELECT id FROM mdl_user WHERE username='dlee' AND deleted=0" | tr -d '[:space:]')
    if [ -n "$DLEE_ID" ]; then
        DLEE_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_groups_members WHERE groupid=$GROUP_B_ID AND userid=$DLEE_ID" | tr -d '[:space:]')
        [ "$DLEE_CHECK" -gt 0 ] 2>/dev/null && DLEE_IN_B="true"
    fi

    echo "Group B found: ID=$GROUP_B_ID, Members=$GROUP_B_MEMBER_COUNT, dlee=$DLEE_IN_B"
else
    echo "Discussion Group B NOT found"
fi

# Check course group mode (0=No groups, 1=Separate, 2=Visible)
COURSE_GROUPMODE=$(moodle_query "SELECT groupmode FROM mdl_course WHERE id=$COURSE_ID" | tr -d '[:space:]')
COURSE_GROUPMODE=${COURSE_GROUPMODE:-0}
echo "Course group mode: $COURSE_GROUPMODE"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/groups_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_group_count": ${INITIAL_GROUP_COUNT:-0},
    "current_group_count": ${CURRENT_GROUP_COUNT:-0},
    "group_a_found": $GROUP_A_FOUND,
    "group_a_id": "$GROUP_A_ID",
    "group_a_member_count": ${GROUP_A_MEMBER_COUNT:-0},
    "bbrown_in_group_a": $BBROWN_IN_A,
    "cgarcia_in_group_a": $CGARCIA_IN_A,
    "group_b_found": $GROUP_B_FOUND,
    "group_b_id": "$GROUP_B_ID",
    "group_b_member_count": ${GROUP_B_MEMBER_COUNT:-0},
    "dlee_in_group_b": $DLEE_IN_B,
    "course_groupmode": $COURSE_GROUPMODE,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/setup_course_groups_result.json

echo ""
cat /tmp/setup_course_groups_result.json
echo ""
echo "=== Export Complete ==="
