#!/bin/bash
# Export script for Create Workshop Peer Assessment task

echo "=== Exporting Create Workshop Result ==="

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

# Get stored values
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
INITIAL_WORKSHOP_COUNT=$(cat /tmp/initial_workshop_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current workshop count
CURRENT_WORKSHOP_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_workshop WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_WORKSHOP_COUNT=${CURRENT_WORKSHOP_COUNT:-0}

echo "Workshop count: initial=$INITIAL_WORKSHOP_COUNT, current=$CURRENT_WORKSHOP_COUNT"

# Look for the target workshop (case-insensitive match)
# We look for the most recently modified workshop that matches the name partially
WORKSHOP_DATA=$(moodle_query "SELECT id, name, strategy, grade, gradinggrade, phase, timemodified FROM mdl_workshop WHERE course=$COURSE_ID AND LOWER(name) LIKE '%lab report%' AND LOWER(name) LIKE '%peer review%' ORDER BY id DESC LIMIT 1")

WORKSHOP_FOUND="false"
WORKSHOP_ID=""
WORKSHOP_NAME=""
STRATEGY=""
GRADE_SUBMISSION="0"
GRADE_ASSESSMENT="0"
PHASE="0"
TIMEMODIFIED="0"
CRITERIA_COUNT="0"
CRITERIA_DESCRIPTIONS=""

if [ -n "$WORKSHOP_DATA" ]; then
    WORKSHOP_FOUND="true"
    WORKSHOP_ID=$(echo "$WORKSHOP_DATA" | cut -f1 | tr -d '[:space:]')
    WORKSHOP_NAME=$(echo "$WORKSHOP_DATA" | cut -f2)
    STRATEGY=$(echo "$WORKSHOP_DATA" | cut -f3)
    GRADE_SUBMISSION=$(echo "$WORKSHOP_DATA" | cut -f4 | tr -d '[:space:]')
    GRADE_ASSESSMENT=$(echo "$WORKSHOP_DATA" | cut -f5 | tr -d '[:space:]')
    PHASE=$(echo "$WORKSHOP_DATA" | cut -f6 | tr -d '[:space:]')
    TIMEMODIFIED=$(echo "$WORKSHOP_DATA" | cut -f7 | tr -d '[:space:]')
    
    # Format float grades to integers for comparison if they are whole numbers
    GRADE_SUBMISSION=${GRADE_SUBMISSION%.*}
    GRADE_ASSESSMENT=${GRADE_ASSESSMENT%.*}

    echo "Workshop found: ID=$WORKSHOP_ID, Name='$WORKSHOP_NAME', Strategy='$STRATEGY', Phase=$PHASE"
    
    # If strategy is accumulative, check criteria
    if [ "$STRATEGY" = "accumulative" ]; then
        CRITERIA_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_workshop_form_accumulative WHERE workshopid=$WORKSHOP_ID" | tr -d '[:space:]')
        # Get descriptions concatenated for keyword search
        CRITERIA_DESCRIPTIONS=$(moodle_query "SELECT description FROM mdl_workshop_form_accumulative WHERE workshopid=$WORKSHOP_ID")
        echo "Accumulative criteria count: $CRITERIA_COUNT"
    else
        echo "Strategy is not accumulative (found: $STRATEGY), skipping criteria check"
    fi
else
    echo "Target workshop NOT found in course $COURSE_ID"
fi

# Verify workshop is in the correct course
WORKSHOP_COURSE_ID=""
if [ -n "$WORKSHOP_ID" ]; then
    WORKSHOP_COURSE_ID=$(moodle_query "SELECT course FROM mdl_workshop WHERE id=$WORKSHOP_ID" | tr -d '[:space:]')
fi

# Check if newly created
NEWLY_CREATED="false"
if [ "$TIMEMODIFIED" -gt "$TASK_START_TIME" ]; then
    NEWLY_CREATED="true"
fi

# Escape for JSON
WORKSHOP_NAME_ESC=$(echo "$WORKSHOP_NAME" | sed 's/"/\\"/g')
CRITERIA_DESCRIPTIONS_ESC=$(echo "$CRITERIA_DESCRIPTIONS" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_workshop_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_workshop_count": ${INITIAL_WORKSHOP_COUNT:-0},
    "current_workshop_count": ${CURRENT_WORKSHOP_COUNT:-0},
    "workshop_found": $WORKSHOP_FOUND,
    "workshop_id": "$WORKSHOP_ID",
    "workshop_name": "$WORKSHOP_NAME_ESC",
    "workshop_course_id": "$WORKSHOP_COURSE_ID",
    "strategy": "$STRATEGY",
    "grade_submission": ${GRADE_SUBMISSION:-0},
    "grade_assessment": ${GRADE_ASSESSMENT:-0},
    "phase": ${PHASE:-0},
    "timemodified": ${TIMEMODIFIED:-0},
    "task_start_time": ${TASK_START_TIME:-0},
    "newly_created": $NEWLY_CREATED,
    "criteria_count": ${CRITERIA_COUNT:-0},
    "criteria_descriptions": "$CRITERIA_DESCRIPTIONS_ESC",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_workshop_result.json

echo ""
cat /tmp/create_workshop_result.json
echo ""
echo "=== Export Complete ==="