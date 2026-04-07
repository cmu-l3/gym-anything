#!/bin/bash
# Export script for Configure Self Enrollment task

echo "=== Exporting Configure Self Enrollment Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
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
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Get Course ID
COURSE_ID=$(cat /tmp/chem101_id.txt 2>/dev/null)
if [ -z "$COURSE_ID" ]; then
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')
fi

# Get Initial State
INITIAL_STATE=$(cat /tmp/initial_self_enrol_state.txt 2>/dev/null || echo "")

# Get Current Self-Enrollment Instances
# We fetch all fields needed for verification
# Schema: id, status (0=enabled), password, customint3 (max users), enrolperiod (seconds), name
echo "Querying self-enrollment configuration..."
CURRENT_DATA=$(moodle_query "SELECT id, status, password, customint3, enrolperiod, name FROM mdl_enrol WHERE courseid=$COURSE_ID AND enrol='self' ORDER BY id DESC")

# Parse rows (there might be multiple, though usually one per course)
# We will verify if ANY instance matches the requirements
# JSON structure will hold a list of instances

instances_json="["
first="true"

# Read line by line
while IFS=$'\t' read -r id status password max_users duration name; do
    if [ "$first" = "true" ]; then
        first="false"
    else
        instances_json="$instances_json,"
    fi
    
    # Escape name and password for JSON
    name_esc=$(echo "$name" | sed 's/"/\\"/g')
    pass_esc=$(echo "$password" | sed 's/"/\\"/g')
    
    instances_json="$instances_json {
        \"id\": \"$id\",
        \"status\": \"$status\",
        \"password\": \"$pass_esc\",
        \"max_users\": \"$max_users\",
        \"duration\": \"$duration\",
        \"name\": \"$name_esc\"
    }"
done <<< "$CURRENT_DATA"

instances_json="$instances_json]"

# Check if data found (if CURRENT_DATA is empty, parsing loop won't run properly for the first element check)
if [ -z "$CURRENT_DATA" ]; then
    instances_json="[]"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/self_enrol_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": "$COURSE_ID",
    "initial_state_hash": "$(echo "$INITIAL_STATE" | md5sum | cut -d' ' -f1)",
    "instances": $instances_json,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_self_enrollment_result.json

echo ""
echo "Result:"
cat /tmp/configure_self_enrollment_result.json
echo ""
echo "=== Export Complete ==="