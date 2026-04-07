#!/bin/bash
# Export script for Configure Completion Tracking task

echo "=== Exporting Completion Tracking Result ==="

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

# Retrieve context
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_CRITERIA_COUNT=$(cat /tmp/initial_criteria_count 2>/dev/null || echo "0")

if [ "$COURSE_ID" = "0" ]; then
    # Emergency lookup
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
fi

# 1. Check if completion tracking is enabled for the course
ENABLE_COMPLETION=$(moodle_query "SELECT enablecompletion FROM mdl_course WHERE id=$COURSE_ID" | tr -d '[:space:]')
ENABLE_COMPLETION=${ENABLE_COMPLETION:-0}

# 2. Function to check activity details
check_activity() {
    local name_pattern="$1"
    # Find page ID
    local page_id=$(moodle_query "SELECT id FROM mdl_page WHERE course=$COURSE_ID AND LOWER(name) LIKE '$name_pattern' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    
    if [ -n "$page_id" ]; then
        # Find Course Module ID (cmid) - join needed because completion settings are in course_modules
        # We need the 'page' module ID first
        local module_id=$(moodle_query "SELECT id FROM mdl_modules WHERE name='page'" | tr -d '[:space:]')
        
        local cm_data=$(moodle_query "SELECT id, completion, completionview, added FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$module_id AND instance=$page_id")
        
        if [ -n "$cm_data" ]; then
            local cm_id=$(echo "$cm_data" | cut -f1)
            local completion=$(echo "$cm_data" | cut -f2)
            local completionview=$(echo "$cm_data" | cut -f3)
            local timeadded=$(echo "$cm_data" | cut -f4)
            
            # Check if this specific activity is in the course completion criteria
            # Criteriatype 4 = Activity completion
            local criteria_exists=$(moodle_query "SELECT COUNT(*) FROM mdl_course_completion_criteria WHERE course=$COURSE_ID AND criteriatype=4 AND moduleinstance=$cm_id" | tr -d '[:space:]')
            
            # Return JSON object for this activity
            echo "{\"found\": true, \"id\": $page_id, \"cm_id\": $cm_id, \"completion\": ${completion:-0}, \"completionview\": ${completionview:-0}, \"timeadded\": ${timeadded:-0}, \"in_course_criteria\": ${criteria_exists:-0}}"
            return
        fi
    fi
    echo "{\"found\": false}"
}

# Check Activity 1: "Required Reading: Cell Biology"
ACT_1_JSON=$(check_activity "%required reading%cell biology%")

# Check Activity 2: "Lab Safety Guidelines"
ACT_2_JSON=$(check_activity "%lab safety guidelines%")

# 3. Check overall course completion configuration
# Criteriatype 4 is Activity Completion
TOTAL_ACTIVITY_CRITERIA=$(moodle_query "SELECT COUNT(*) FROM mdl_course_completion_criteria WHERE course=$COURSE_ID AND criteriatype=4" | tr -d '[:space:]')
TOTAL_ACTIVITY_CRITERIA=${TOTAL_ACTIVITY_CRITERIA:-0}

# Check aggregation method (1=All, 2=Any). If no row exists, default is usually All.
# We check mdl_course_completion_aggr_methd for criteriatype 4 (Activity) or NULL (Overall)
# Note: Moodle's schema for this is complex. Simpler check is usually sufficient:
# Are there multiple criteria rows?
AGGREGATION_METHOD=$(moodle_query "SELECT method FROM mdl_course_completion_aggr_methd WHERE course=$COURSE_ID AND criteriatype IS NULL" | tr -d '[:space:]')
# If NULL/Empty, it defaults to ALL (1) in most versions for specific criteria types, verify via count.

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/completion_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "task_start_time": ${TASK_START:-0},
    "completion_tracking_enabled": $ENABLE_COMPLETION,
    "initial_criteria_count": ${INITIAL_CRITERIA_COUNT:-0},
    "total_activity_criteria_count": $TOTAL_ACTIVITY_CRITERIA,
    "activity_1": $ACT_1_JSON,
    "activity_2": $ACT_2_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/completion_tracking_result.json

echo ""
cat /tmp/completion_tracking_result.json
echo ""
echo "=== Export Complete ==="