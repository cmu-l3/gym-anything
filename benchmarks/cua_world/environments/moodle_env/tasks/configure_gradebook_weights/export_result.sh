#!/bin/bash
# Export script for Configure Gradebook Weights task

echo "=== Exporting Gradebook Weights Result ==="

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

# Get baselines
INITIAL_CATEGORY_COUNT=$(cat /tmp/initial_grade_category_count 2>/dev/null || echo "0")
INITIAL_AGGREGATION=$(cat /tmp/initial_aggregation 2>/dev/null || echo "13")

# Current sub-category count (depth > 1 means non-root)
CURRENT_CATEGORY_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth > 1" | tr -d '[:space:]')
CURRENT_CATEGORY_COUNT=${CURRENT_CATEGORY_COUNT:-0}

# Root category aggregation method
# Moodle aggregation codes: 0=Mean, 10=Weighted mean, 11=Simple weighted mean, 13=Natural
ROOT_AGGREGATION=$(moodle_query "SELECT aggregation FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth=1 LIMIT 1" | tr -d '[:space:]')
ROOT_AGGREGATION=${ROOT_AGGREGATION:-13}

echo "Grade categories: initial=$INITIAL_CATEGORY_COUNT, current=$CURRENT_CATEGORY_COUNT"
echo "Root aggregation: $ROOT_AGGREGATION (initial was $INITIAL_AGGREGATION)"

# Look for "Lab Reports" category and its weight
LAB_REPORTS_FOUND="false"
LAB_REPORTS_WEIGHT="0"
LAB_REPORTS_DATA=$(moodle_query "SELECT gc.id, gc.fullname, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance = gc.id AND gi.itemtype = 'category' AND gi.courseid = gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%lab reports%' AND gc.depth > 1 LIMIT 1")

if [ -n "$LAB_REPORTS_DATA" ]; then
    LAB_REPORTS_FOUND="true"
    LAB_REPORTS_WEIGHT=$(echo "$LAB_REPORTS_DATA" | cut -f3 | tr -d '[:space:]')
    echo "Lab Reports category found, weight=$LAB_REPORTS_WEIGHT"
else
    echo "Lab Reports category NOT found"
fi

# Look for "Exams" category and its weight
EXAMS_FOUND="false"
EXAMS_WEIGHT="0"
EXAMS_DATA=$(moodle_query "SELECT gc.id, gc.fullname, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance = gc.id AND gi.itemtype = 'category' AND gi.courseid = gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%exams%' AND gc.depth > 1 LIMIT 1")

if [ -n "$EXAMS_DATA" ]; then
    EXAMS_FOUND="true"
    EXAMS_WEIGHT=$(echo "$EXAMS_DATA" | cut -f3 | tr -d '[:space:]')
    echo "Exams category found, weight=$EXAMS_WEIGHT"
else
    echo "Exams category NOT found"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/gradebook_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_category_count": ${INITIAL_CATEGORY_COUNT:-0},
    "current_category_count": ${CURRENT_CATEGORY_COUNT:-0},
    "initial_aggregation": ${INITIAL_AGGREGATION:-13},
    "root_aggregation": ${ROOT_AGGREGATION:-13},
    "lab_reports_found": $LAB_REPORTS_FOUND,
    "lab_reports_weight": "$LAB_REPORTS_WEIGHT",
    "exams_found": $EXAMS_FOUND,
    "exams_weight": "$EXAMS_WEIGHT",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_gradebook_weights_result.json

echo ""
cat /tmp/configure_gradebook_weights_result.json
echo ""
echo "=== Export Complete ==="
