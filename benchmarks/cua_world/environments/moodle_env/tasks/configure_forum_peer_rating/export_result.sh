#!/bin/bash
# Export script for Configure Forum Peer Rating task

echo "=== Exporting Configure Forum Peer Rating Result ==="

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

# Get BIO101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

# Find the forum
# Look for exact name first, then partial if needed (though description requires specific name)
echo "Searching for forum..."
FORUM_DATA=$(moodle_query "SELECT id, name, assessed, scale FROM mdl_forum WHERE course=$COURSE_ID AND name='Nature vs Nurture Debate' ORDER BY id DESC LIMIT 1")

FORUM_FOUND="false"
FORUM_ID=""
FORUM_NAME=""
AGGREGATE_TYPE="0"
SCALE="0"
PERMISSION_OVERRIDDEN="false"
CONTEXT_LEVEL="0"

if [ -n "$FORUM_DATA" ]; then
    FORUM_FOUND="true"
    FORUM_ID=$(echo "$FORUM_DATA" | cut -f1 | tr -d '[:space:]')
    FORUM_NAME=$(echo "$FORUM_DATA" | cut -f2)
    AGGREGATE_TYPE=$(echo "$FORUM_DATA" | cut -f3 | tr -d '[:space:]')
    SCALE=$(echo "$FORUM_DATA" | cut -f4 | tr -d '[:space:]')
    
    echo "Forum found: ID=$FORUM_ID, Name='$FORUM_NAME', Assessed=$AGGREGATE_TYPE, Scale=$SCALE"

    # Check Permissions
    # 1. Get Course Module ID for this forum
    # 2. Get Context ID for this Course Module (contextlevel=70)
    # 3. Check role_capabilities
    
    # Get Module ID for 'forum'
    MODULE_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='forum'" | tr -d '[:space:]')
    
    # Get Course Module ID
    CM_ID=$(moodle_query "SELECT id FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$MODULE_ID AND instance=$FORUM_ID" | tr -d '[:space:]')
    
    if [ -n "$CM_ID" ]; then
        # Get Context ID
        CONTEXT_DATA=$(moodle_query "SELECT id, contextlevel FROM mdl_context WHERE instanceid=$CM_ID AND contextlevel=70 LIMIT 1")
        CONTEXT_ID=$(echo "$CONTEXT_DATA" | cut -f1 | tr -d '[:space:]')
        CONTEXT_LEVEL=$(echo "$CONTEXT_DATA" | cut -f2 | tr -d '[:space:]')
        
        if [ -n "$CONTEXT_ID" ]; then
            # Get Student Role ID
            STUDENT_ROLE_ID=$(moodle_query "SELECT id FROM mdl_role WHERE shortname='student'" | tr -d '[:space:]')
            
            # Check capability 'mod/forum:rate' for Student in this Context
            PERMISSION=$(moodle_query "SELECT permission FROM mdl_role_capabilities WHERE contextid=$CONTEXT_ID AND roleid=$STUDENT_ROLE_ID AND capability='mod/forum:rate'" | tr -d '[:space:]')
            
            # permission: 1 = ALLOW
            if [ "$PERMISSION" = "1" ]; then
                PERMISSION_OVERRIDDEN="true"
                echo "Permission override found: mod/forum:rate is ALLOWED for Student in Context $CONTEXT_ID"
            else
                echo "Permission override NOT found (Permission value: $PERMISSION)"
            fi
        else
            echo "Context not found for CM_ID $CM_ID"
        fi
    else
        echo "Course Module not found for Forum $FORUM_ID"
    fi

else
    echo "Forum 'Nature vs Nurture Debate' NOT found in BIO101"
fi

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FORUM_CREATED_TIME="0"
NEWLY_CREATED="false"

if [ -n "$FORUM_ID" ]; then
    # Check timemodified or timecreated
    FORUM_CREATED_TIME=$(moodle_query "SELECT timemodified FROM mdl_forum WHERE id=$FORUM_ID" | tr -d '[:space:]')
    if [ "$FORUM_CREATED_TIME" -gt "$TASK_START" ]; then
        NEWLY_CREATED="true"
    fi
fi

# Escape for JSON
FORUM_NAME_ESC=$(echo "$FORUM_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/forum_rating_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "forum_found": $FORUM_FOUND,
    "forum_id": "$FORUM_ID",
    "forum_name": "$FORUM_NAME_ESC",
    "aggregate_type": ${AGGREGATE_TYPE:-0},
    "scale": ${SCALE:-0},
    "permission_overridden": $PERMISSION_OVERRIDDEN,
    "context_level": ${CONTEXT_LEVEL:-0},
    "newly_created": $NEWLY_CREATED,
    "task_start": $TASK_START,
    "forum_time": ${FORUM_CREATED_TIME:-0}
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_forum_peer_rating_result.json

echo ""
cat /tmp/configure_forum_peer_rating_result.json
echo ""
echo "=== Export Complete ==="