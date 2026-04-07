#!/bin/bash
# Export script for Configure Activity Groupings task

echo "=== Exporting Configure Activity Groupings Result ==="

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

take_screenshot /tmp/task_end_screenshot.png

# Load context
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
INITIAL_GROUPING_COUNT=$(cat /tmp/initial_grouping_count 2>/dev/null || echo "0")
INITIAL_ASSIGN_COUNT=$(cat /tmp/initial_assign_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Grouping "Lab Sections"
GROUPING_DATA=$(moodle_query "SELECT id, timecreated FROM mdl_groupings WHERE courseid=$COURSE_ID AND name='Lab Sections' LIMIT 1")
GROUPING_EXISTS="false"
GROUPING_ID=""
GROUPING_CREATED_DURING_TASK="false"

if [ -n "$GROUPING_DATA" ]; then
    GROUPING_EXISTS="true"
    GROUPING_ID=$(echo "$GROUPING_DATA" | cut -f1)
    G_TIME=$(echo "$GROUPING_DATA" | cut -f2)
    if [ "$G_TIME" -ge "$TASK_START" ]; then
        GROUPING_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Group Membership in Grouping
# Need IDs for "Monday Lab" and "Thursday Lab"
G1_ID=$(moodle_query "SELECT id FROM mdl_groups WHERE courseid=$COURSE_ID AND name='Monday Lab'")
G2_ID=$(moodle_query "SELECT id FROM mdl_groups WHERE courseid=$COURSE_ID AND name='Thursday Lab'")

MONDAY_IN_GROUPING="false"
THURSDAY_IN_GROUPING="false"

if [ "$GROUPING_EXISTS" = "true" ] && [ -n "$G1_ID" ]; then
    CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_groupings_groups WHERE groupingid=$GROUPING_ID AND groupid=$G1_ID")
    [ "$CHECK" -gt 0 ] && MONDAY_IN_GROUPING="true"
fi

if [ "$GROUPING_EXISTS" = "true" ] && [ -n "$G2_ID" ]; then
    CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_groupings_groups WHERE groupingid=$GROUPING_ID AND groupid=$G2_ID")
    [ "$CHECK" -gt 0 ] && THURSDAY_IN_GROUPING="true"
fi

# 3. Check Assignment "Lab Report 1"
ASSIGN_DATA=$(moodle_query "SELECT id, timemodified FROM mdl_assign WHERE course=$COURSE_ID AND name='Lab Report 1' LIMIT 1")
ASSIGN_EXISTS="false"
ASSIGN_ID=""
ASSIGN_CREATED_DURING_TASK="false"
ASSIGN_GROUPING_CORRECT="false"
ASSIGN_GROUPMODE_CORRECT="false"

if [ -n "$ASSIGN_DATA" ]; then
    ASSIGN_EXISTS="true"
    ASSIGN_ID=$(echo "$ASSIGN_DATA" | cut -f1)
    A_TIME=$(echo "$ASSIGN_DATA" | cut -f2)
    if [ "$A_TIME" -ge "$TASK_START" ]; then
        ASSIGN_CREATED_DURING_TASK="true"
    fi

    # Check Course Module settings for this assignment
    # Need to join mdl_course_modules with mdl_modules to find the 'assign' instance
    # module id for 'assign'
    MOD_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='assign'")
    
    CM_DATA=$(moodle_query "SELECT groupingid, groupmode FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$MOD_ID AND instance=$ASSIGN_ID")
    
    if [ -n "$CM_DATA" ]; then
        CM_GROUPING=$(echo "$CM_DATA" | cut -f1)
        CM_GROUPMODE=$(echo "$CM_DATA" | cut -f2)
        
        # Check grouping ID match
        if [ "$CM_GROUPING" = "$GROUPING_ID" ] && [ "$GROUPING_EXISTS" = "true" ]; then
            ASSIGN_GROUPING_CORRECT="true"
        fi
        
        # Check groupmode (1 = Separate, 2 = Visible)
        if [ "$CM_GROUPMODE" -eq 1 ] || [ "$CM_GROUPMODE" -eq 2 ]; then
            ASSIGN_GROUPMODE_CORRECT="true"
        fi
    fi
fi

# JSON Export
TEMP_JSON=$(mktemp /tmp/grouping_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "grouping_exists": $GROUPING_EXISTS,
    "grouping_created_during_task": $GROUPING_CREATED_DURING_TASK,
    "monday_lab_included": $MONDAY_IN_GROUPING,
    "thursday_lab_included": $THURSDAY_IN_GROUPING,
    "assignment_exists": $ASSIGN_EXISTS,
    "assignment_created_during_task": $ASSIGN_CREATED_DURING_TASK,
    "assignment_grouping_correct": $ASSIGN_GROUPING_CORRECT,
    "assignment_groupmode_correct": $ASSIGN_GROUPMODE_CORRECT,
    "initial_grouping_count": ${INITIAL_GROUPING_COUNT:-0},
    "initial_assign_count": ${INITIAL_ASSIGN_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_activity_groupings_result.json

echo ""
cat /tmp/configure_activity_groupings_result.json
echo ""
echo "=== Export Complete ==="