#!/bin/bash
# Export script for Create Course Badges task

echo "=== Exporting Course Badges Result ==="

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

# Get Counts
INITIAL_COUNT=$(cat /tmp/initial_badge_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_badge WHERE courseid=$COURSE_ID" | tr -d '[:space:]')
CURRENT_COUNT=${CURRENT_COUNT:-0}

echo "Badge count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# --- Badge 1 Verification: Lab Safety Certified ---
BADGE1_DATA=$(moodle_query "SELECT id, status FROM mdl_badge WHERE courseid=$COURSE_ID AND LOWER(name) LIKE '%lab safety certified%' ORDER BY id DESC LIMIT 1")

BADGE1_FOUND="false"
BADGE1_ID=""
BADGE1_STATUS="0"
BADGE1_CRITERIA_TYPE="0"
BADGE1_ROLE_PARAM=""

if [ -n "$BADGE1_DATA" ]; then
    BADGE1_FOUND="true"
    BADGE1_ID=$(echo "$BADGE1_DATA" | cut -f1 | tr -d '[:space:]')
    BADGE1_STATUS=$(echo "$BADGE1_DATA" | cut -f2 | tr -d '[:space:]')
    
    # Check criteria type (2 = Manual issue by role)
    # Note: criteriatype 0 (overall) is always present, we check for specific type
    BADGE1_CRITERIA_TYPE=$(moodle_query "SELECT criteriatype FROM mdl_badge_criteria WHERE badgeid=$BADGE1_ID AND criteriatype=2 LIMIT 1" | tr -d '[:space:]')
    
    # Check role parameter (should be Teacher)
    # First get the criteria ID for type 2
    CRIT_ID=$(moodle_query "SELECT id FROM mdl_badge_criteria WHERE badgeid=$BADGE1_ID AND criteriatype=2 LIMIT 1" | tr -d '[:space:]')
    
    if [ -n "$CRIT_ID" ]; then
        # Get the role ID stored in params
        ROLE_ID=$(moodle_query "SELECT value FROM mdl_badge_criteria_param WHERE critid=$CRIT_ID AND name='role' LIMIT 1" | tr -d '[:space:]')
        if [ -n "$ROLE_ID" ]; then
            # Get role shortname
            BADGE1_ROLE_PARAM=$(moodle_query "SELECT shortname FROM mdl_role WHERE id=$ROLE_ID" | tr -d '[:space:]')
        fi
    fi
    echo "Badge 1 found: ID=$BADGE1_ID, Status=$BADGE1_STATUS, Type=$BADGE1_CRITERIA_TYPE, Role=$BADGE1_ROLE_PARAM"
else
    echo "Badge 1 'Lab Safety Certified' NOT found"
fi

# --- Badge 2 Verification: Biology Course Complete ---
BADGE2_DATA=$(moodle_query "SELECT id, status FROM mdl_badge WHERE courseid=$COURSE_ID AND LOWER(name) LIKE '%biology course complete%' ORDER BY id DESC LIMIT 1")

BADGE2_FOUND="false"
BADGE2_ID=""
BADGE2_STATUS="0"
BADGE2_CRITERIA_TYPE="0"

if [ -n "$BADGE2_DATA" ]; then
    BADGE2_FOUND="true"
    BADGE2_ID=$(echo "$BADGE2_DATA" | cut -f1 | tr -d '[:space:]')
    BADGE2_STATUS=$(echo "$BADGE2_DATA" | cut -f2 | tr -d '[:space:]')
    
    # Check criteria type (4 = Course completion)
    BADGE2_CRITERIA_TYPE=$(moodle_query "SELECT criteriatype FROM mdl_badge_criteria WHERE badgeid=$BADGE2_ID AND criteriatype=4 LIMIT 1" | tr -d '[:space:]')
    
    echo "Badge 2 found: ID=$BADGE2_ID, Status=$BADGE2_STATUS, Type=$BADGE2_CRITERIA_TYPE"
else
    echo "Badge 2 'Biology Course Complete' NOT found"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/badges_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "badge1": {
        "found": $BADGE1_FOUND,
        "id": "$BADGE1_ID",
        "status": ${BADGE1_STATUS:-0},
        "criteria_type": ${BADGE1_CRITERIA_TYPE:-0},
        "role_param": "$BADGE1_ROLE_PARAM"
    },
    "badge2": {
        "found": $BADGE2_FOUND,
        "id": "$BADGE2_ID",
        "status": ${BADGE2_STATUS:-0},
        "criteria_type": ${BADGE2_CRITERIA_TYPE:-0}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_course_badges_result.json

echo ""
cat /tmp/create_course_badges_result.json
echo ""
echo "=== Export Complete ==="