#!/bin/bash
# Export script for Configure Tiered Assessment Pathway task
# Queries the NUR401 course state and writes a JSON result file for the verifier.

echo "=== Exporting Tiered Assessment Pathway Result ==="

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

# ---------------------------------------------------------------------------
# Resolve course ID
# ---------------------------------------------------------------------------
COURSE_ID=$(cat /tmp/nur401_course_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='NUR401'" | tr -d '[:space:]')
fi
COURSE_ID=${COURSE_ID:-0}
echo "NUR401 Course ID: $COURSE_ID"

# Helper: escape string for JSON embedding
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "$s"
}

# =========================================================================
# 1. QUIZ — "Drug Classification Exam"
# =========================================================================
QUIZ_FOUND="false"
QUIZ_ID="0"
QUIZ_NAME=""
QUIZ_TIMELIMIT="0"
QUIZ_ATTEMPTS="0"
QUIZ_GRADEPASS="0"
QUIZ_CMID="0"
QUIZ_COMPLETION="0"
QUIZ_COMPLETIONPASSGRADE="0"
QUIZ_SLOT_COUNT="0"

if [ "$COURSE_ID" != "0" ]; then
    QUIZ_DATA=$(moodle_query "SELECT id, name, timelimit, attempts FROM mdl_quiz WHERE course=$COURSE_ID AND LOWER(name) LIKE '%drug classification%' ORDER BY id DESC LIMIT 1")
    if [ -n "$QUIZ_DATA" ]; then
        QUIZ_FOUND="true"
        QUIZ_ID=$(echo "$QUIZ_DATA" | cut -f1 | tr -d '[:space:]')
        QUIZ_NAME=$(echo "$QUIZ_DATA" | cut -f2)
        QUIZ_TIMELIMIT=$(echo "$QUIZ_DATA" | cut -f3 | tr -d '[:space:]')
        QUIZ_ATTEMPTS=$(echo "$QUIZ_DATA" | cut -f4 | tr -d '[:space:]')

        # Grade-to-pass from grade_items
        QUIZ_GRADEPASS=$(moodle_query "SELECT gradepass FROM mdl_grade_items WHERE itemtype='mod' AND itemmodule='quiz' AND iteminstance=$QUIZ_ID LIMIT 1" | tr -d '[:space:]')

        # Course module info
        QUIZ_MOD_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='quiz'" | tr -d '[:space:]')
        QUIZ_CM_RAW=$(moodle_query "SELECT id, completion, completionpassgrade FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$QUIZ_MOD_ID AND instance=$QUIZ_ID ORDER BY id DESC LIMIT 1")
        QUIZ_CMID=$(echo "$QUIZ_CM_RAW" | cut -f1 | tr -d '[:space:]')
        QUIZ_COMPLETION=$(echo "$QUIZ_CM_RAW" | cut -f2 | tr -d '[:space:]')
        QUIZ_COMPLETIONPASSGRADE=$(echo "$QUIZ_CM_RAW" | cut -f3 | tr -d '[:space:]')

        # Count question slots
        QUIZ_SLOT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_slots WHERE quizid=$QUIZ_ID" | tr -d '[:space:]')

        echo "Quiz found: ID=$QUIZ_ID Name='$QUIZ_NAME' timelimit=$QUIZ_TIMELIMIT attempts=$QUIZ_ATTEMPTS gradepass=$QUIZ_GRADEPASS"
        echo "  cmid=$QUIZ_CMID completion=$QUIZ_COMPLETION passgrade=$QUIZ_COMPLETIONPASSGRADE slots=$QUIZ_SLOT_COUNT"
    else
        echo "Quiz 'Drug Classification Exam' NOT found"
    fi
fi

QUIZ_TIMELIMIT=${QUIZ_TIMELIMIT:-0}
QUIZ_ATTEMPTS=${QUIZ_ATTEMPTS:-0}
QUIZ_GRADEPASS=${QUIZ_GRADEPASS:-0}
QUIZ_CMID=${QUIZ_CMID:-0}
QUIZ_COMPLETION=${QUIZ_COMPLETION:-0}
QUIZ_COMPLETIONPASSGRADE=${QUIZ_COMPLETIONPASSGRADE:-0}
QUIZ_SLOT_COUNT=${QUIZ_SLOT_COUNT:-0}

# =========================================================================
# 2. PAGE — "Pharmacokinetics Reading"
# =========================================================================
PAGE_FOUND="false"
PAGE_CMID="0"
PAGE_COMPLETION="0"
PAGE_COMPLETIONVIEW="0"

if [ "$COURSE_ID" != "0" ]; then
    PAGE_ID=$(moodle_query "SELECT id FROM mdl_page WHERE course=$COURSE_ID AND LOWER(name) LIKE '%pharmacokinetics%' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')
    if [ -n "$PAGE_ID" ] && [ "$PAGE_ID" != "0" ]; then
        PAGE_FOUND="true"
        PAGE_MOD_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='page'" | tr -d '[:space:]')
        PAGE_CM_RAW=$(moodle_query "SELECT id, completion, completionview FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$PAGE_MOD_ID AND instance=$PAGE_ID ORDER BY id DESC LIMIT 1")
        PAGE_CMID=$(echo "$PAGE_CM_RAW" | cut -f1 | tr -d '[:space:]')
        PAGE_COMPLETION=$(echo "$PAGE_CM_RAW" | cut -f2 | tr -d '[:space:]')
        PAGE_COMPLETIONVIEW=$(echo "$PAGE_CM_RAW" | cut -f3 | tr -d '[:space:]')
        echo "Page found: cmid=$PAGE_CMID completion=$PAGE_COMPLETION completionview=$PAGE_COMPLETIONVIEW"
    else
        echo "Page 'Pharmacokinetics Reading' NOT found"
    fi
fi

PAGE_CMID=${PAGE_CMID:-0}
PAGE_COMPLETION=${PAGE_COMPLETION:-0}
PAGE_COMPLETIONVIEW=${PAGE_COMPLETIONVIEW:-0}

# =========================================================================
# 3. ASSIGNMENT — "Medication Safety Case Study"
# =========================================================================
ASSIGN_FOUND="false"
ASSIGN_ID="0"
ASSIGN_CMID="0"
ASSIGN_GRADE="0"
ASSIGN_GRADEPASS="0"
ASSIGN_COMPLETION="0"
ASSIGN_COMPLETIONSUBMIT="0"
ASSIGN_AVAILABILITY=""

if [ "$COURSE_ID" != "0" ]; then
    ASSIGN_DATA=$(moodle_query "SELECT id, name, grade FROM mdl_assign WHERE course=$COURSE_ID AND LOWER(name) LIKE '%medication safety%' ORDER BY id DESC LIMIT 1")
    if [ -n "$ASSIGN_DATA" ]; then
        ASSIGN_FOUND="true"
        ASSIGN_ID=$(echo "$ASSIGN_DATA" | cut -f1 | tr -d '[:space:]')
        ASSIGN_GRADE=$(echo "$ASSIGN_DATA" | cut -f3 | tr -d '[:space:]')

        # Grade-to-pass
        ASSIGN_GRADEPASS=$(moodle_query "SELECT gradepass FROM mdl_grade_items WHERE itemtype='mod' AND itemmodule='assign' AND iteminstance=$ASSIGN_ID LIMIT 1" | tr -d '[:space:]')

        # Course module info
        ASSIGN_MOD_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='assign'" | tr -d '[:space:]')
        ASSIGN_CM_RAW=$(moodle_query "SELECT id, completion, availability FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$ASSIGN_MOD_ID AND instance=$ASSIGN_ID ORDER BY id DESC LIMIT 1")
        ASSIGN_CMID=$(echo "$ASSIGN_CM_RAW" | cut -f1 | tr -d '[:space:]')
        ASSIGN_COMPLETION=$(echo "$ASSIGN_CM_RAW" | cut -f2 | tr -d '[:space:]')
        ASSIGN_AVAILABILITY=$(echo "$ASSIGN_CM_RAW" | cut -f3)

        # Completionsubmit from assign table
        ASSIGN_COMPLETIONSUBMIT=$(moodle_query "SELECT completionsubmit FROM mdl_assign WHERE id=$ASSIGN_ID" | tr -d '[:space:]')

        echo "Assignment found: ID=$ASSIGN_ID cmid=$ASSIGN_CMID grade=$ASSIGN_GRADE gradepass=$ASSIGN_GRADEPASS"
        echo "  completion=$ASSIGN_COMPLETION completionsubmit=$ASSIGN_COMPLETIONSUBMIT"
        echo "  availability=$ASSIGN_AVAILABILITY"
    else
        echo "Assignment 'Medication Safety Case Study' NOT found"
    fi
fi

ASSIGN_ID=${ASSIGN_ID:-0}
ASSIGN_CMID=${ASSIGN_CMID:-0}
ASSIGN_GRADE=${ASSIGN_GRADE:-0}
ASSIGN_GRADEPASS=${ASSIGN_GRADEPASS:-0}
ASSIGN_COMPLETION=${ASSIGN_COMPLETION:-0}
ASSIGN_COMPLETIONSUBMIT=${ASSIGN_COMPLETIONSUBMIT:-0}

# Escape availability for JSON
ASSIGN_AVAIL_ESC=$(echo "$ASSIGN_AVAILABILITY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

# =========================================================================
# 4. FORUM — "Clinical Drug Interaction Analysis"
# =========================================================================
FORUM_FOUND="false"
FORUM_ID="0"
FORUM_CMID="0"
FORUM_TYPE=""
FORUM_ASSESSED="0"
FORUM_SCALE="0"
FORUM_COMPLETION="0"
FORUM_COMPLETIONPOSTS="0"
FORUM_COMPLETIONDISCUSSIONS="0"
FORUM_AVAILABILITY=""

if [ "$COURSE_ID" != "0" ]; then
    FORUM_DATA=$(moodle_query "SELECT id, name, type, assessed, scale FROM mdl_forum WHERE course=$COURSE_ID AND LOWER(name) LIKE '%drug interaction%' ORDER BY id DESC LIMIT 1")
    if [ -n "$FORUM_DATA" ]; then
        FORUM_FOUND="true"
        FORUM_ID=$(echo "$FORUM_DATA" | cut -f1 | tr -d '[:space:]')
        FORUM_TYPE=$(echo "$FORUM_DATA" | cut -f3 | tr -d '[:space:]')
        FORUM_ASSESSED=$(echo "$FORUM_DATA" | cut -f4 | tr -d '[:space:]')
        FORUM_SCALE=$(echo "$FORUM_DATA" | cut -f5 | tr -d '[:space:]')

        # Course module info
        FORUM_MOD_ID=$(moodle_query "SELECT id FROM mdl_modules WHERE name='forum'" | tr -d '[:space:]')
        FORUM_CM_RAW=$(moodle_query "SELECT id, completion, availability FROM mdl_course_modules WHERE course=$COURSE_ID AND module=$FORUM_MOD_ID AND instance=$FORUM_ID ORDER BY id DESC LIMIT 1")
        FORUM_CMID=$(echo "$FORUM_CM_RAW" | cut -f1 | tr -d '[:space:]')
        FORUM_COMPLETION=$(echo "$FORUM_CM_RAW" | cut -f2 | tr -d '[:space:]')
        FORUM_AVAILABILITY=$(echo "$FORUM_CM_RAW" | cut -f3)

        # Forum completion fields
        FORUM_POSTS_RAW=$(moodle_query "SELECT completionposts, completiondiscussions FROM mdl_forum WHERE id=$FORUM_ID" | tr '\t' ',')
        FORUM_COMPLETIONPOSTS=$(echo "$FORUM_POSTS_RAW" | cut -d',' -f1 | tr -d '[:space:]')
        FORUM_COMPLETIONDISCUSSIONS=$(echo "$FORUM_POSTS_RAW" | cut -d',' -f2 | tr -d '[:space:]')

        echo "Forum found: ID=$FORUM_ID type=$FORUM_TYPE assessed=$FORUM_ASSESSED scale=$FORUM_SCALE"
        echo "  cmid=$FORUM_CMID completion=$FORUM_COMPLETION posts=$FORUM_COMPLETIONPOSTS discussions=$FORUM_COMPLETIONDISCUSSIONS"
        echo "  availability=$FORUM_AVAILABILITY"
    else
        echo "Forum 'Clinical Drug Interaction Analysis' NOT found"
    fi
fi

FORUM_ID=${FORUM_ID:-0}
FORUM_CMID=${FORUM_CMID:-0}
FORUM_TYPE=${FORUM_TYPE:-}
FORUM_ASSESSED=${FORUM_ASSESSED:-0}
FORUM_SCALE=${FORUM_SCALE:-0}
FORUM_COMPLETION=${FORUM_COMPLETION:-0}
FORUM_COMPLETIONPOSTS=${FORUM_COMPLETIONPOSTS:-0}
FORUM_COMPLETIONDISCUSSIONS=${FORUM_COMPLETIONDISCUSSIONS:-0}

# Escape forum availability for JSON
FORUM_AVAIL_ESC=$(echo "$FORUM_AVAILABILITY" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

# =========================================================================
# 5. GRADEBOOK — weighted mean, 3 categories
# =========================================================================
TOPLEVEL_AGG=$(moodle_query "SELECT aggregation FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth=1 LIMIT 1" | tr -d '[:space:]')
TOPLEVEL_AGG=${TOPLEVEL_AGG:-0}
echo "Top-level gradebook aggregation: $TOPLEVEL_AGG (10=Weighted mean)"

# Foundation category
FOUND_CAT_FOUND="false"
FOUND_CAT_WEIGHT="0"
FOUND_CAT_DATA=$(moodle_query "SELECT gc.id, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance=gc.id AND gi.itemtype='category' AND gi.courseid=gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%foundation%' AND gc.depth > 1 LIMIT 1")
if [ -n "$FOUND_CAT_DATA" ]; then
    FOUND_CAT_FOUND="true"
    FOUND_CAT_WEIGHT=$(echo "$FOUND_CAT_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    echo "Foundation category found, weight=$FOUND_CAT_WEIGHT"
fi

# Application category
APP_CAT_FOUND="false"
APP_CAT_WEIGHT="0"
APP_CAT_DATA=$(moodle_query "SELECT gc.id, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance=gc.id AND gi.itemtype='category' AND gi.courseid=gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%application%' AND gc.depth > 1 LIMIT 1")
if [ -n "$APP_CAT_DATA" ]; then
    APP_CAT_FOUND="true"
    APP_CAT_WEIGHT=$(echo "$APP_CAT_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    echo "Application category found, weight=$APP_CAT_WEIGHT"
fi

# Synthesis category
SYN_CAT_FOUND="false"
SYN_CAT_WEIGHT="0"
SYN_CAT_DATA=$(moodle_query "SELECT gc.id, COALESCE(gi.aggregationcoef, 0) FROM mdl_grade_categories gc LEFT JOIN mdl_grade_items gi ON gi.iteminstance=gc.id AND gi.itemtype='category' AND gi.courseid=gc.courseid WHERE gc.courseid=$COURSE_ID AND LOWER(gc.fullname) LIKE '%synthesis%' AND gc.depth > 1 LIMIT 1")
if [ -n "$SYN_CAT_DATA" ]; then
    SYN_CAT_FOUND="true"
    SYN_CAT_WEIGHT=$(echo "$SYN_CAT_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    echo "Synthesis category found, weight=$SYN_CAT_WEIGHT"
fi

# Count grade items in sub-categories (not at top level)
TOP_CAT_ID=$(moodle_query "SELECT id FROM mdl_grade_categories WHERE courseid=$COURSE_ID AND depth=1 LIMIT 1" | tr -d '[:space:]')
TOP_CAT_ID=${TOP_CAT_ID:-0}
ITEMS_IN_SUBCATS="0"
if [ "$TOP_CAT_ID" != "0" ]; then
    ITEMS_IN_SUBCATS=$(moodle_query "SELECT COUNT(*) FROM mdl_grade_items WHERE courseid=$COURSE_ID AND itemtype='mod' AND categoryid != $TOP_CAT_ID" | tr -d '[:space:]')
fi
ITEMS_IN_SUBCATS=${ITEMS_IN_SUBCATS:-0}
echo "Grade items in sub-categories: $ITEMS_IN_SUBCATS"

# =========================================================================
# 6. COURSE COMPLETION
# =========================================================================
COMPLETION_CRITERIA_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_completion_criteria WHERE course=$COURSE_ID" | tr -d '[:space:]')
COMPLETION_CRITERIA_COUNT=${COMPLETION_CRITERIA_COUNT:-0}
echo "Course completion criteria count: $COMPLETION_CRITERIA_COUNT"

# =========================================================================
# 7. Write result JSON
# =========================================================================
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

QUIZ_NAME_ESC=$(json_escape "$QUIZ_NAME")
FORUM_TYPE_ESC=$(json_escape "$FORUM_TYPE")

TEMP_JSON=$(mktemp /tmp/tiered_assessment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": ${TASK_START:-0},
    "course_id": $COURSE_ID,
    "quiz_found": $QUIZ_FOUND,
    "quiz_id": ${QUIZ_ID:-0},
    "quiz_name": "$QUIZ_NAME_ESC",
    "quiz_timelimit": ${QUIZ_TIMELIMIT:-0},
    "quiz_attempts": ${QUIZ_ATTEMPTS:-0},
    "quiz_gradepass": "${QUIZ_GRADEPASS:-0}",
    "quiz_cmid": ${QUIZ_CMID:-0},
    "quiz_completion": ${QUIZ_COMPLETION:-0},
    "quiz_completionpassgrade": ${QUIZ_COMPLETIONPASSGRADE:-0},
    "quiz_slot_count": ${QUIZ_SLOT_COUNT:-0},
    "page_found": $PAGE_FOUND,
    "page_cmid": ${PAGE_CMID:-0},
    "page_completion": ${PAGE_COMPLETION:-0},
    "page_completionview": ${PAGE_COMPLETIONVIEW:-0},
    "assign_found": $ASSIGN_FOUND,
    "assign_id": ${ASSIGN_ID:-0},
    "assign_cmid": ${ASSIGN_CMID:-0},
    "assign_grade": "${ASSIGN_GRADE:-0}",
    "assign_gradepass": "${ASSIGN_GRADEPASS:-0}",
    "assign_completion": ${ASSIGN_COMPLETION:-0},
    "assign_completionsubmit": ${ASSIGN_COMPLETIONSUBMIT:-0},
    "assign_availability": "$ASSIGN_AVAIL_ESC",
    "forum_found": $FORUM_FOUND,
    "forum_id": ${FORUM_ID:-0},
    "forum_cmid": ${FORUM_CMID:-0},
    "forum_type": "$FORUM_TYPE_ESC",
    "forum_assessed": ${FORUM_ASSESSED:-0},
    "forum_scale": ${FORUM_SCALE:-0},
    "forum_completion": ${FORUM_COMPLETION:-0},
    "forum_completionposts": ${FORUM_COMPLETIONPOSTS:-0},
    "forum_completiondiscussions": ${FORUM_COMPLETIONDISCUSSIONS:-0},
    "forum_availability": "$FORUM_AVAIL_ESC",
    "gradebook_aggregation": ${TOPLEVEL_AGG:-0},
    "foundation_cat_found": $FOUND_CAT_FOUND,
    "foundation_cat_weight": "$FOUND_CAT_WEIGHT",
    "application_cat_found": $APP_CAT_FOUND,
    "application_cat_weight": "$APP_CAT_WEIGHT",
    "synthesis_cat_found": $SYN_CAT_FOUND,
    "synthesis_cat_weight": "$SYN_CAT_WEIGHT",
    "items_in_subcategories": ${ITEMS_IN_SUBCATS:-0},
    "course_completion_criteria_count": ${COMPLETION_CRITERIA_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/tiered_assessment_result.json

echo ""
cat /tmp/tiered_assessment_result.json
echo ""
echo "=== Export Complete ==="
