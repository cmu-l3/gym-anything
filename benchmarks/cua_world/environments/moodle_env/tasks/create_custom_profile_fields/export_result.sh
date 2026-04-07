#!/bin/bash
# Export script for Create Custom Profile Fields task

echo "=== Exporting Custom Profile Fields Result ==="

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

# Load initial counts
INITIAL_CAT_COUNT=$(cat /tmp/initial_cat_count 2>/dev/null || echo "0")
INITIAL_FIELD_COUNT=$(cat /tmp/initial_field_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_CAT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_user_info_category" | tr -d '[:space:]')
CURRENT_FIELD_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_user_info_field" | tr -d '[:space:]')

echo "Categories: $INITIAL_CAT_COUNT -> $CURRENT_CAT_COUNT"
echo "Fields: $INITIAL_FIELD_COUNT -> $CURRENT_FIELD_COUNT"

# --- CHECK CATEGORY ---
CAT_DATA=$(moodle_query "SELECT id, name FROM mdl_user_info_category WHERE LOWER(name) LIKE '%employee information%' LIMIT 1")
CAT_FOUND="false"
CAT_ID=""
CAT_NAME=""

if [ -n "$CAT_DATA" ]; then
    CAT_FOUND="true"
    CAT_ID=$(echo "$CAT_DATA" | cut -f1 | tr -d '[:space:]')
    CAT_NAME=$(echo "$CAT_DATA" | cut -f2)
    echo "Category found: $CAT_NAME (ID: $CAT_ID)"
else
    echo "Category 'Employee Information' NOT found"
fi

# --- CHECK FIELDS ---

# Function to get field data
get_field_data() {
    local shortname="$1"
    # Select: id, datatype, categoryid, required, locked, defaultdata, param1
    moodle_query "SELECT id, datatype, categoryid, required, locked, defaultdata, param1 FROM mdl_user_info_field WHERE shortname='$shortname' LIMIT 1"
}

# Field 1: employeeid
FIELD_EID_DATA=$(get_field_data "employeeid")
EID_FOUND="false"
EID_DETAILS="{}"

if [ -n "$FIELD_EID_DATA" ]; then
    EID_FOUND="true"
    EID_ID=$(echo "$FIELD_EID_DATA" | cut -f1)
    EID_TYPE=$(echo "$FIELD_EID_DATA" | cut -f2)
    EID_CAT=$(echo "$FIELD_EID_DATA" | cut -f3)
    EID_REQ=$(echo "$FIELD_EID_DATA" | cut -f4)
    EID_LOCK=$(echo "$FIELD_EID_DATA" | cut -f5)
    EID_DETAILS="{\"id\": \"$EID_ID\", \"datatype\": \"$EID_TYPE\", \"categoryid\": \"$EID_CAT\", \"required\": $EID_REQ, \"locked\": $EID_LOCK}"
fi

# Field 2: department
FIELD_DEPT_DATA=$(get_field_data "department")
DEPT_FOUND="false"
DEPT_DETAILS="{}"

if [ -n "$FIELD_DEPT_DATA" ]; then
    DEPT_FOUND="true"
    DEPT_ID=$(echo "$FIELD_DEPT_DATA" | cut -f1)
    DEPT_TYPE=$(echo "$FIELD_DEPT_DATA" | cut -f2)
    DEPT_CAT=$(echo "$FIELD_DEPT_DATA" | cut -f3)
    DEPT_REQ=$(echo "$FIELD_DEPT_DATA" | cut -f4)
    # param1 contains menu options, newlines need escaping for JSON
    DEPT_PARAM1=$(echo "$FIELD_DEPT_DATA" | cut -f7 | awk '{printf "%s\\n", $0}' | sed 's/"/\\"/g')
    DEPT_DETAILS="{\"id\": \"$DEPT_ID\", \"datatype\": \"$DEPT_TYPE\", \"categoryid\": \"$DEPT_CAT\", \"required\": $DEPT_REQ, \"param1\": \"$DEPT_PARAM1\"}"
fi

# Field 3: joblevel
FIELD_JOB_DATA=$(get_field_data "joblevel")
JOB_FOUND="false"
JOB_DETAILS="{}"

if [ -n "$FIELD_JOB_DATA" ]; then
    JOB_FOUND="true"
    JOB_ID=$(echo "$FIELD_JOB_DATA" | cut -f1)
    JOB_TYPE=$(echo "$FIELD_JOB_DATA" | cut -f2)
    JOB_CAT=$(echo "$FIELD_JOB_DATA" | cut -f3)
    JOB_DEFAULT=$(echo "$FIELD_JOB_DATA" | cut -f6 | sed 's/"/\\"/g')
    JOB_DETAILS="{\"id\": \"$JOB_ID\", \"datatype\": \"$JOB_TYPE\", \"categoryid\": \"$JOB_CAT\", \"defaultdata\": \"$JOB_DEFAULT\"}"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/profile_fields_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_cat_count": ${INITIAL_CAT_COUNT:-0},
    "current_cat_count": ${CURRENT_CAT_COUNT:-0},
    "initial_field_count": ${INITIAL_FIELD_COUNT:-0},
    "current_field_count": ${CURRENT_FIELD_COUNT:-0},
    "category_found": $CAT_FOUND,
    "category_id": "${CAT_ID:-0}",
    "fields": {
        "employeeid": $EID_DETAILS,
        "department": $DEPT_DETAILS,
        "joblevel": $JOB_DETAILS
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure empty objects are valid JSON if fields not found
if [ "$EID_FOUND" = "false" ]; then sed -i 's/"employeeid": ,/"employeeid": null,/g' "$TEMP_JSON"; fi
if [ "$DEPT_FOUND" = "false" ]; then sed -i 's/"department": ,/"department": null,/g' "$TEMP_JSON"; fi
if [ "$JOB_FOUND" = "false" ]; then sed -i 's/"joblevel": /"joblevel": null/g' "$TEMP_JSON"; fi

# Clean up possible sed mess if trailing comma issue
sed -i 's/: ,/: null,/g' "$TEMP_JSON"
sed -i 's/: }/: null}/g' "$TEMP_JSON"

safe_write_json "$TEMP_JSON" /tmp/create_custom_profile_fields_result.json

echo ""
cat /tmp/create_custom_profile_fields_result.json
echo ""
echo "=== Export Complete ==="