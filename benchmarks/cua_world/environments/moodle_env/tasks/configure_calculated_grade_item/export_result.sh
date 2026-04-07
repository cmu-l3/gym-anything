#!/bin/bash
# Export script for Calculated Grade Item task

echo "=== Exporting Calculated Grade Item Result ==="

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
    moodle_query_json() {
        # Helper to output JSON-formatted query result
        # Assumes columns: id, itemname, idnumber, calculation
        local query="$1"
        local method=$(_get_mariadb_method)
        
        # We construct a JSON array manually from the tab-separated output
        echo "["
        local first=true
        
        if [ "$method" = "docker" ]; then
             QUERY_CMD="docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e"
        else
             QUERY_CMD="mysql -u moodleuser -pmoodlepass moodle -N -B -e"
        fi
        
        $QUERY_CMD "$query" | while read -r id itemname idnumber calculation; do
            if [ "$first" = true ]; then first=false; else echo ","; fi
            # Escape JSON special chars
            safe_itemname=$(echo "$itemname" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            safe_idnumber=$(echo "$idnumber" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            safe_calc=$(echo "$calculation" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            
            # Handle NULLs
            [ "$safe_idnumber" == "NULL" ] && safe_idnumber=""
            [ "$safe_calc" == "NULL" ] && safe_calc=""
            
            echo -n "{\"id\": $id, \"itemname\": \"$safe_itemname\", \"idnumber\": \"$safe_idnumber\", \"calculation\": \"$safe_calc\"}"
        done
        echo ""
        echo "]"
    }
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get CHEM101 course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM101'" | tr -d '[:space:]')

echo "Analyzing grade items for course $COURSE_ID..."

# Get all grade items for the course
# Columns: id, itemname, idnumber, calculation
# calculation field contains the formula (e.g., =[[#123]] + [[#124]])
ITEMS_JSON=$(moodle_query_json "SELECT id, itemname, idnumber, calculation FROM mdl_grade_items WHERE courseid=$COURSE_ID ORDER BY id ASC")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/grade_calc_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "grade_items": $ITEMS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/configure_calculated_grade_item_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/configure_calculated_grade_item_result.json
chmod 666 /tmp/configure_calculated_grade_item_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/configure_calculated_grade_item_result.json
echo ""
echo "=== Export Complete ==="