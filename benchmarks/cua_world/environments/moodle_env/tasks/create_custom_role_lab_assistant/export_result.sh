#!/bin/bash
# Export script for Create Custom Role task

echo "=== Exporting Create Custom Role Result ==="

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

# Get baseline count
INITIAL_ROLE_COUNT=$(cat /tmp/initial_role_count 2>/dev/null || echo "0")
CURRENT_ROLE_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_role" | tr -d '[:space:]')
CURRENT_ROLE_COUNT=${CURRENT_ROLE_COUNT:-0}

echo "Role count: initial=$INITIAL_ROLE_COUNT, current=$CURRENT_ROLE_COUNT"

# Look for the target role
ROLE_DATA=$(moodle_query "SELECT id, shortname, name, archetype FROM mdl_role WHERE shortname='labassistant'")

ROLE_FOUND="false"
ROLE_ID=""
ROLE_SHORTNAME=""
ROLE_FULLNAME=""
ROLE_ARCHETYPE=""
CAPABILITY_PERMISSION="0" # Default 0 (Not set/Inherit)
CONTEXT_COURSE="false"

if [ -n "$ROLE_DATA" ]; then
    ROLE_FOUND="true"
    ROLE_ID=$(echo "$ROLE_DATA" | cut -f1 | tr -d '[:space:]')
    ROLE_SHORTNAME=$(echo "$ROLE_DATA" | cut -f2)
    ROLE_FULLNAME=$(echo "$ROLE_DATA" | cut -f3)
    ROLE_ARCHETYPE=$(echo "$ROLE_DATA" | cut -f4)

    echo "Role found: ID=$ROLE_ID, Short='$ROLE_SHORTNAME', Full='$ROLE_FULLNAME', Arch='$ROLE_ARCHETYPE'"

    # Check capability: moodle/course:manageactivities
    # permission: 1=Allow, -1=Prohibit, -1000=Prevent
    # contextid=1 is System context
    CAP_CHECK=$(moodle_query "SELECT permission FROM mdl_role_capabilities WHERE roleid=$ROLE_ID AND capability='moodle/course:manageactivities' AND contextid=1" | tr -d '[:space:]')
    if [ -n "$CAP_CHECK" ]; then
        CAPABILITY_PERMISSION="$CAP_CHECK"
    fi
    echo "Manage Activities Permission: $CAPABILITY_PERMISSION"

    # Check if role allows course context assignment
    # Currently context levels are stored in mdl_role_context_levels (Moodle 4.x)
    # Context level 50 is COURSE
    CONTEXT_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_role_context_levels WHERE roleid=$ROLE_ID AND contextlevel=50" | tr -d '[:space:]')
    if [ "$CONTEXT_CHECK" -gt 0 ]; then
        CONTEXT_COURSE="true"
    fi
    echo "Course context assignable: $CONTEXT_COURSE"
else
    echo "Role 'labassistant' NOT found"
fi

# Escape for JSON
ROLE_FULLNAME_ESC=$(echo "$ROLE_FULLNAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_role_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_role_count": ${INITIAL_ROLE_COUNT:-0},
    "current_role_count": ${CURRENT_ROLE_COUNT:-0},
    "role_found": $ROLE_FOUND,
    "role_id": "$ROLE_ID",
    "role_shortname": "$ROLE_SHORTNAME",
    "role_fullname": "$ROLE_FULLNAME_ESC",
    "role_archetype": "$ROLE_ARCHETYPE",
    "capability_permission": $CAPABILITY_PERMISSION,
    "context_course_enabled": $CONTEXT_COURSE,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_custom_role_result.json

echo ""
cat /tmp/create_custom_role_result.json
echo ""
echo "=== Export Complete ==="