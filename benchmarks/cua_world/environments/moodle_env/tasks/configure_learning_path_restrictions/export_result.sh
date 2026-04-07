#!/bin/bash
# Export script for Configure Learning Path Restrictions task

echo "=== Exporting Learning Path Result ==="

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

COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null)
if [ -z "$COURSE_ID" ]; then
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')
fi

# Helper to get info for a specific module name
# Returns JSON object string with: id, cmid, completion, availability
get_module_info() {
    local mod_name_pattern="$1"
    
    # 1. Find the page instance ID
    local page_id=$(moodle_query "SELECT id FROM mdl_page WHERE course=$COURSE_ID AND LOWER(name) LIKE '%$mod_name_pattern%' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    
    if [ -z "$page_id" ]; then
        echo "{}"
        return
    fi
    
    # 2. Find the Course Module ID (cmid)
    # module=15 is typically 'page', but let's be safe and look it up
    local page_mod_id=$(moodle_query "SELECT id FROM mdl_modules WHERE name='page'" | tr -d '[:space:]')
    
    # Get CM info
    local cm_data=$(moodle_query "SELECT id, completion, availability, added FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$page_mod_id AND instance=$page_id ORDER BY id DESC LIMIT 1")
    
    local cm_id=$(echo "$cm_data" | cut -f1)
    local completion=$(echo "$cm_data" | cut -f2)
    local availability=$(echo "$cm_data" | cut -f3)
    local added=$(echo "$cm_data" | cut -f4)
    
    # Escape availability JSON for nesting
    local avail_esc=$(echo "$availability" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    
    echo "{\"exists\": true, \"page_id\": $page_id, \"cm_id\": $cm_id, \"completion\": $completion, \"availability\": \"$avail_esc\", \"added\": $added}"
}

echo "Gathering module data..."

# Get data for all three expected modules
# Using lower case for pattern matching
MOD1_INFO=$(get_module_info "module 1")
MOD2_INFO=$(get_module_info "module 2")
MOD3_INFO=$(get_module_info "module 3")

echo "Module 1 Info: $MOD1_INFO"
echo "Module 2 Info: $MOD2_INFO"
echo "Module 3 Info: $MOD3_INFO"

INITIAL_COUNT=$(cat /tmp/initial_page_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_page WHERE course=$COURSE_ID" | tr -d '[:space:]')
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/learning_path_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "course_id": ${COURSE_ID:-0},
    "initial_page_count": ${INITIAL_COUNT:-0},
    "current_page_count": ${CURRENT_COUNT:-0},
    "module1": $MOD1_INFO,
    "module2": $MOD2_INFO,
    "module3": $MOD3_INFO,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/learning_path_result.json

echo ""
cat /tmp/learning_path_result.json
echo ""
echo "=== Export Complete ==="