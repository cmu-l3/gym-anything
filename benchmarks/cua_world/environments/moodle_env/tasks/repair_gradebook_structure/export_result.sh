#!/bin/bash
# Export script for Repair Gradebook Structure task
# Queries the current CHEM201 gradebook state and writes a JSON result file
# that the verifier reads to determine pass/fail and score.

echo "=== Exporting Repair Gradebook Structure Result ==="

# Source shared utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    . /workspace/scripts/task_utils.sh
else
    echo "Warning: /workspace/scripts/task_utils.sh not found, using inline definitions"
fi

# Fallback definitions in case task_utils.sh did not export them
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
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
        echo "Warning: Could not take screenshot"
        [ -f "$output_file" ] && echo "Screenshot saved: $output_file"
    }
fi

if ! type safe_write_json &>/dev/null; then
    safe_write_json() {
        local temp_file="$1"
        local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"
        chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"
        echo "Result saved to $dest_path"
    }
fi

# ---------------------------------------------------------------------------
# Take final screenshot
# ---------------------------------------------------------------------------
take_screenshot /tmp/task_end_screenshot.png

# ---------------------------------------------------------------------------
# Resolve CHEM201 course ID
# ---------------------------------------------------------------------------
if [ -f /tmp/chem201_course_id ]; then
    COURSE_ID=$(cat /tmp/chem201_course_id | tr -d '[:space:]')
fi

if [ -z "${COURSE_ID:-}" ]; then
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='CHEM201'" | tr -d '[:space:]')
fi

if [ -z "${COURSE_ID:-}" ]; then
    echo "ERROR: CHEM201 course not found in database"
    # Write a minimal failure result so the verifier can report cleanly
    TEMP_JSON=$(mktemp /tmp/repair_gradebook_result.XXXXXX.json)
    cat > "$TEMP_JSON" << EOF
{
    "error": "CHEM201 course not found",
    "course_id": 0,
    "top_aggregation": -1,
    "problem_sets_found": false,
    "problem_sets_weight": "0",
    "lab_reports_found": false,
    "lab_reports_weight": "0",
    "exams_found": false,
    "exams_weight": "0",
    "items_in_correct_categories": 0,
    "midterm_weight": "0",
    "final_weight": "0",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
    safe_write_json "$TEMP_JSON" /tmp/repair_gradebook_structure_result.json
    exit 0
fi

echo "CHEM201 course ID: $COURSE_ID"

# ---------------------------------------------------------------------------
# Query top-level aggregation (depth=1 = root course grade category)
# Moodle codes: 0=Mean, 10=Weighted mean, 11=Simple weighted mean, 13=Natural
# ---------------------------------------------------------------------------
TOPLEVEL_AGG=$(moodle_query "SELECT aggregation FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth=1 LIMIT 1" | tr -d '[:space:]')
TOPLEVEL_AGG=${TOPLEVEL_AGG:-0}
echo "Top-level aggregation code: $TOPLEVEL_AGG (10=Weighted mean is correct)"

# ---------------------------------------------------------------------------
# Check for "Problem Sets" sub-category and its weight at the top level
# The weight is stored in mdl_grade_items.aggregationcoef for the row where
# itemtype='category' and iteminstance=grade_category.id
# ---------------------------------------------------------------------------
PROBLEM_SETS_FOUND="false"
PROBLEM_SETS_WEIGHT="0"

PROBLEM_SETS_DATA=$(moodle_query "SELECT gc.id, gc.fullname, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance=gc.id AND gi.itemtype='category' AND gi.courseid=gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%problem set%' AND gc.depth > 1 LIMIT 1")

if [ -n "$PROBLEM_SETS_DATA" ]; then
    PROBLEM_SETS_FOUND="true"
    PROBLEM_SETS_WEIGHT=$(echo "$PROBLEM_SETS_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    PROBLEM_SETS_WEIGHT=${PROBLEM_SETS_WEIGHT:-0}
    echo "Problem Sets category found, weight=$PROBLEM_SETS_WEIGHT"
else
    echo "Problem Sets category NOT found"
fi

# ---------------------------------------------------------------------------
# Check for "Lab Reports" sub-category and its weight
# ---------------------------------------------------------------------------
LAB_REPORTS_FOUND="false"
LAB_REPORTS_WEIGHT="0"

LAB_REPORTS_DATA=$(moodle_query "SELECT gc.id, gc.fullname, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance=gc.id AND gi.itemtype='category' AND gi.courseid=gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%lab report%' AND gc.depth > 1 LIMIT 1")

if [ -n "$LAB_REPORTS_DATA" ]; then
    LAB_REPORTS_FOUND="true"
    LAB_REPORTS_WEIGHT=$(echo "$LAB_REPORTS_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    LAB_REPORTS_WEIGHT=${LAB_REPORTS_WEIGHT:-0}
    echo "Lab Reports category found, weight=$LAB_REPORTS_WEIGHT"
else
    echo "Lab Reports category NOT found"
fi

# ---------------------------------------------------------------------------
# Check for "Exams" sub-category and its weight
# ---------------------------------------------------------------------------
EXAMS_FOUND="false"
EXAMS_WEIGHT="0"

EXAMS_DATA=$(moodle_query "SELECT gc.id, gc.fullname, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance=gc.id AND gi.itemtype='category' AND gi.courseid=gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%exam%' AND gc.depth > 1 LIMIT 1")

if [ -n "$EXAMS_DATA" ]; then
    EXAMS_FOUND="true"
    EXAMS_WEIGHT=$(echo "$EXAMS_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    EXAMS_WEIGHT=${EXAMS_WEIGHT:-0}
    EXAMS_CAT_ID=$(echo "$EXAMS_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    echo "Exams category found (id=$EXAMS_CAT_ID), weight=$EXAMS_WEIGHT"
else
    echo "Exams category NOT found"
    EXAMS_CAT_ID=""
fi

# ---------------------------------------------------------------------------
# Count how many of the 6 grade items are now in any sub-category
# (i.e., not at the flat top-level any more)
# ---------------------------------------------------------------------------
TOP_CAT_ID=$(moodle_query "SELECT id FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth=1 LIMIT 1" | tr -d '[:space:]')
TOP_CAT_ID=${TOP_CAT_ID:-0}

ITEMS_IN_SUBCATS=0
if [ "$TOP_CAT_ID" != "0" ]; then
    ITEMS_IN_SUBCATS=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemtype='manual' AND categoryid != $TOP_CAT_ID" | tr -d '[:space:]')
    ITEMS_IN_SUBCATS=${ITEMS_IN_SUBCATS:-0}
fi
echo "Grade items moved into sub-categories: $ITEMS_IN_SUBCATS (out of 6)"

# ---------------------------------------------------------------------------
# Check individual item categories (for diagnostic detail)
# ---------------------------------------------------------------------------
for ITEM_NAME in "problem set 1" "problem set 2" "lab report 1" "lab report 2" "midterm exam" "final exam"; do
    ITEM_CAT=$(moodle_query "SELECT gc.fullname FROM mdl_grade_items gi JOIN mdl_grade_categories gc ON gi.categoryid=gc.id WHERE gi.courseid=$COURSE_ID AND LOWER(gi.itemname)='$ITEM_NAME' AND gi.itemtype='manual' LIMIT 1" | tr -d '[:space:]')
    echo "  '$ITEM_NAME' -> category: ${ITEM_CAT:-[top level / not found]}"
done

# ---------------------------------------------------------------------------
# Check Midterm Exam sub-weight within Exams category
# ---------------------------------------------------------------------------
MIDTERM_WEIGHT="0"
FINAL_WEIGHT="0"

if [ -n "$EXAMS_CAT_ID" ] && [ "$EXAMS_CAT_ID" != "0" ]; then
    MIDTERM_WEIGHT=$(moodle_query "SELECT COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_items gi WHERE gi.courseid=$COURSE_ID AND gi.categoryid=$EXAMS_CAT_ID AND LOWER(gi.itemname) LIKE '%midterm%' AND gi.itemtype='manual' LIMIT 1" | tr -d '[:space:]')
    MIDTERM_WEIGHT=${MIDTERM_WEIGHT:-0}

    FINAL_WEIGHT=$(moodle_query "SELECT COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_items gi WHERE gi.courseid=$COURSE_ID AND gi.categoryid=$EXAMS_CAT_ID AND LOWER(gi.itemname) LIKE '%final%' AND gi.itemtype='manual' LIMIT 1" | tr -d '[:space:]')
    FINAL_WEIGHT=${FINAL_WEIGHT:-0}

    echo "Midterm Exam weight within Exams: $MIDTERM_WEIGHT (expected ~40)"
    echo "Final Exam weight within Exams:   $FINAL_WEIGHT (expected ~60)"
else
    # Try the broader search across all sub-categories in case Exams has a different name
    MIDTERM_WEIGHT=$(moodle_query "SELECT COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_items gi JOIN mdl_grade_categories gc ON gi.categoryid=gc.id WHERE gi.courseid=$COURSE_ID AND gc.depth > 1 AND LOWER(gc.fullname) LIKE '%exam%' AND LOWER(gi.itemname) LIKE '%midterm%' AND gi.itemtype='manual' LIMIT 1" | tr -d '[:space:]')
    MIDTERM_WEIGHT=${MIDTERM_WEIGHT:-0}

    FINAL_WEIGHT=$(moodle_query "SELECT COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_items gi JOIN mdl_grade_categories gc ON gi.categoryid=gc.id WHERE gi.courseid=$COURSE_ID AND gc.depth > 1 AND LOWER(gc.fullname) LIKE '%exam%' AND LOWER(gi.itemname) LIKE '%final%' AND gi.itemtype='manual' LIMIT 1" | tr -d '[:space:]')
    FINAL_WEIGHT=${FINAL_WEIGHT:-0}

    echo "Midterm weight (broad search): $MIDTERM_WEIGHT"
    echo "Final weight (broad search):   $FINAL_WEIGHT"
fi

# ---------------------------------------------------------------------------
# Retrieve baseline values saved by setup script
# ---------------------------------------------------------------------------
INITIAL_CAT_COUNT=$(cat /tmp/chem201_initial_cat_count 2>/dev/null | tr -d '[:space:]' || echo "0")
INITIAL_AGG=$(cat /tmp/chem201_initial_agg 2>/dev/null | tr -d '[:space:]' || echo "0")

# ---------------------------------------------------------------------------
# Write result JSON
# ---------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/repair_gradebook_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_cat_count": ${INITIAL_CAT_COUNT:-0},
    "initial_aggregation": ${INITIAL_AGG:-0},
    "top_aggregation": ${TOPLEVEL_AGG:-0},
    "problem_sets_found": $PROBLEM_SETS_FOUND,
    "problem_sets_weight": "$PROBLEM_SETS_WEIGHT",
    "lab_reports_found": $LAB_REPORTS_FOUND,
    "lab_reports_weight": "$LAB_REPORTS_WEIGHT",
    "exams_found": $EXAMS_FOUND,
    "exams_weight": "$EXAMS_WEIGHT",
    "items_in_correct_categories": ${ITEMS_IN_SUBCATS:-0},
    "midterm_weight": "$MIDTERM_WEIGHT",
    "final_weight": "$FINAL_WEIGHT",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/repair_gradebook_structure_result.json

echo ""
cat /tmp/repair_gradebook_structure_result.json
echo ""
echo "=== Export Complete ==="
