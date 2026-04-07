#!/bin/bash
# Export script for Import Offline Grades task

echo "=== Exporting Import Offline Grades Result ==="

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
take_screenshot /tmp/task_final.png

# Read setup data
TARGET_GRADE_ITEM_ID=$(cat /tmp/target_grade_item_id 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

echo "Checking grades for item ID: $TARGET_GRADE_ITEM_ID"

# Function to get grade for a user email
# Returns: "itemid|finalgrade|timemodified"
get_student_grade() {
    local email="$1"
    # Find user ID
    local uid=$(moodle_query "SELECT id FROM mdl_user WHERE email='$email'" | tr -d '[:space:]')
    
    if [ -z "$uid" ]; then
        echo "0|0|0"
        return
    fi
    
    # Query grade_grades for this user
    # We join with grade_items to find WHAT item they were graded in
    # We prefer the TARGET item, but if they created a new one, we want to know that too.
    # Logic: Look for the most recently modified grade for this user in BIO101
    # We'll fetch the grade for the specific target item first
    
    local target_grade=$(moodle_query "SELECT finalgrade, timemodified FROM mdl_grade_grades WHERE itemid=$TARGET_GRADE_ITEM_ID AND userid=$uid")
    
    if [ -n "$target_grade" ]; then
        local grade=$(echo "$target_grade" | cut -f1)
        local time=$(echo "$target_grade" | cut -f2)
        echo "$TARGET_GRADE_ITEM_ID|$grade|$time"
    else
        # If no grade in target item, check if they created a new item named "Practical Result" (default from CSV)
        # or anything else recently modified
        local other_grade=$(moodle_query "
            SELECT gg.itemid, gg.finalgrade, gg.timemodified 
            FROM mdl_grade_grades gg
            JOIN mdl_grade_items gi ON gg.itemid = gi.id
            JOIN mdl_course c ON gi.courseid = c.id
            WHERE gg.userid = $uid 
            AND c.shortname = 'BIO101'
            AND gi.itemtype = 'manual'
            AND gg.timemodified > $TASK_START_TIME
            ORDER BY gg.timemodified DESC LIMIT 1
        ")
        
        if [ -n "$other_grade" ]; then
            local oid=$(echo "$other_grade" | cut -f1)
            local ograde=$(echo "$other_grade" | cut -f2)
            local otime=$(echo "$other_grade" | cut -f3)
            echo "$oid|$ograde|$otime"
        else
            echo "0|0|0"
        fi
    fi
}

# Check grades for the 3 students
GRADE_JSMITH=$(get_student_grade "jsmith@example.com")
GRADE_MJONES=$(get_student_grade "mjones@example.com")
GRADE_AWILSON=$(get_student_grade "awilson@example.com")

echo "JSmith Data: $GRADE_JSMITH"
echo "MJones Data: $GRADE_MJONES"
echo "AWilson Data: $GRADE_AWILSON"

# Parse JSmith
JSMITH_ITEM=$(echo "$GRADE_JSMITH" | cut -d'|' -f1)
JSMITH_VAL=$(echo "$GRADE_JSMITH" | cut -d'|' -f2)
JSMITH_TIME=$(echo "$GRADE_JSMITH" | cut -d'|' -f3)

# Parse MJones
MJONES_ITEM=$(echo "$GRADE_MJONES" | cut -d'|' -f1)
MJONES_VAL=$(echo "$GRADE_MJONES" | cut -d'|' -f2)
MJONES_TIME=$(echo "$GRADE_MJONES" | cut -d'|' -f3)

# Parse AWilson
AWILSON_ITEM=$(echo "$GRADE_AWILSON" | cut -d'|' -f1)
AWILSON_VAL=$(echo "$GRADE_AWILSON" | cut -d'|' -f2)
AWILSON_TIME=$(echo "$GRADE_AWILSON" | cut -d'|' -f3)

# If the agent created a new item instead of mapping, get its name for feedback
CREATED_ITEM_NAME=""
if [ "$JSMITH_ITEM" != "0" ] && [ "$JSMITH_ITEM" != "$TARGET_GRADE_ITEM_ID" ]; then
    CREATED_ITEM_NAME=$(moodle_query "SELECT itemname FROM mdl_grade_items WHERE id=$JSMITH_ITEM")
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/import_grades_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_item_id": $TARGET_GRADE_ITEM_ID,
    "task_start_time": $TASK_START_TIME,
    "created_item_name": "$CREATED_ITEM_NAME",
    "students": {
        "jsmith": {
            "item_id": $JSMITH_ITEM,
            "grade": ${JSMITH_VAL:-0},
            "timemodified": ${JSMITH_TIME:-0}
        },
        "mjones": {
            "item_id": $MJONES_ITEM,
            "grade": ${MJONES_VAL:-0},
            "timemodified": ${MJONES_TIME:-0}
        },
        "awilson": {
            "item_id": $AWILSON_ITEM,
            "grade": ${AWILSON_VAL:-0},
            "timemodified": ${AWILSON_TIME:-0}
        }
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/import_grades_result.json

echo ""
echo "Result:"
cat /tmp/import_grades_result.json
echo ""
echo "=== Export Complete ==="