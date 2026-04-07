#!/bin/bash
# Export script for Auto Generate Course Groups task

echo "=== Exporting Auto Generate Groups Result ==="

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
    moodle_query_headers() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
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
echo "Course ID: $COURSE_ID"

# 1. Check if Grouping 'Lab Partnerships' exists
GROUPING_DATA=$(moodle_query "SELECT id, name, timecreated FROM mdl_groupings WHERE courseid=$COURSE_ID AND LOWER(name)='lab partnerships' LIMIT 1")
GROUPING_EXISTS="false"
GROUPING_ID=""
GROUPING_TIMECREATED="0"

if [ -n "$GROUPING_DATA" ]; then
    GROUPING_EXISTS="true"
    GROUPING_ID=$(echo "$GROUPING_DATA" | cut -f1 | tr -d '[:space:]')
    GROUPING_TIMECREATED=$(echo "$GROUPING_DATA" | cut -f3 | tr -d '[:space:]')
fi

# 2. Check for created groups matching pattern "Lab Pair %"
# We expect multiple groups, so we count them
LAB_PAIR_GROUPS_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_groups WHERE courseid=$COURSE_ID AND name LIKE 'Lab Pair %'" | tr -d '[:space:]')
LAB_PAIR_GROUPS_COUNT=${LAB_PAIR_GROUPS_COUNT:-0}

# 3. Check if these groups are linked to the grouping
LINKED_GROUPS_COUNT="0"
if [ "$GROUPING_EXISTS" = "true" ] && [ "$LAB_PAIR_GROUPS_COUNT" -gt 0 ]; then
    LINKED_GROUPS_COUNT=$(moodle_query "
        SELECT COUNT(*) 
        FROM mdl_groupings_groups gg 
        JOIN mdl_groups g ON gg.groupid = g.id 
        WHERE gg.groupingid = $GROUPING_ID 
        AND g.name LIKE 'Lab Pair %'
    " | tr -d '[:space:]')
fi

# 4. Check membership statistics
# We want to see if the groups actually have members (should be ~2 per group)
AVG_MEMBER_COUNT="0"
TOTAL_MEMBERS_ASSIGNED="0"
GROUPS_WITH_MEMBERS="0"
GROUPS_WITH_EXACTLY_TWO="0"

if [ "$LAB_PAIR_GROUPS_COUNT" -gt 0 ]; then
    # Get stats on members in these groups
    STATS=$(moodle_query "
        SELECT 
            COUNT(gm.userid) as total_members,
            COUNT(DISTINCT gm.groupid) as groups_with_members
        FROM mdl_groups_members gm
        JOIN mdl_groups g ON gm.groupid = g.id
        WHERE g.courseid = $COURSE_ID AND g.name LIKE 'Lab Pair %'
    ")
    
    TOTAL_MEMBERS_ASSIGNED=$(echo "$STATS" | cut -f1 | tr -d '[:space:]')
    GROUPS_WITH_MEMBERS=$(echo "$STATS" | cut -f2 | tr -d '[:space:]')
    
    # Calculate average
    if [ "$LAB_PAIR_GROUPS_COUNT" -gt 0 ]; then
        # integer math approximation
        AVG_MEMBER_COUNT=$(( TOTAL_MEMBERS_ASSIGNED / LAB_PAIR_GROUPS_COUNT ))
    fi

    # Check how many have exactly 2 members
    GROUPS_WITH_EXACTLY_TWO=$(moodle_query "
        SELECT COUNT(*) FROM (
            SELECT groupid, COUNT(userid) as c 
            FROM mdl_groups_members gm 
            JOIN mdl_groups g ON gm.groupid = g.id 
            WHERE g.courseid = $COURSE_ID AND g.name LIKE 'Lab Pair %'
            GROUP BY groupid
            HAVING c = 2
        ) as counts
    " | tr -d '[:space:]')
fi

# Anti-gaming timestamp check
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$GROUPING_TIMECREATED" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Debug output
echo "Grouping Exists: $GROUPING_EXISTS"
echo "Lab Pair Groups Count: $LAB_PAIR_GROUPS_COUNT"
echo "Linked Groups Count: $LINKED_GROUPS_COUNT"
echo "Groups with exactly 2 members: $GROUPS_WITH_EXACTLY_TWO"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/groups_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "grouping_exists": $GROUPING_EXISTS,
    "grouping_id": "$GROUPING_ID",
    "lab_pair_groups_count": ${LAB_PAIR_GROUPS_COUNT:-0},
    "linked_groups_count": ${LINKED_GROUPS_COUNT:-0},
    "total_members_assigned": ${TOTAL_MEMBERS_ASSIGNED:-0},
    "groups_with_exactly_two": ${GROUPS_WITH_EXACTLY_TWO:-0},
    "created_during_task": $CREATED_DURING_TASK,
    "task_start_time": $TASK_START,
    "grouping_created_time": $GROUPING_TIMECREATED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/auto_generate_groups_result.json

echo ""
cat /tmp/auto_generate_groups_result.json
echo ""
echo "=== Export Complete ==="