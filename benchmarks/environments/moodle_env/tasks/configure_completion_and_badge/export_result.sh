#!/bin/bash
# Export script for Configure Completion and Badge task.
# Reads database state after the agent has completed its work and writes
# /tmp/configure_completion_and_badge_result.json for the verifier.

echo "=== Exporting Configure Completion and Badge Result ==="

# ---------------------------------------------------------------------------
# Source shared utilities with fallback inline definitions
# ---------------------------------------------------------------------------
if [ -f /workspace/scripts/task_utils.sh ]; then
    . /workspace/scripts/task_utils.sh
else
    echo "Warning: /workspace/scripts/task_utils.sh not found, using inline definitions"
fi

if ! type moodle_query &>/dev/null 2>&1; then
    echo "Warning: moodle_query not available from task_utils.sh, defining inline"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method
        method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
fi

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
fi

if ! type safe_write_json &>/dev/null 2>&1; then
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
# Retrieve course ID
# ---------------------------------------------------------------------------
COURSE_ID=$(cat /tmp/bio302_course_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$COURSE_ID" ] || [ "$COURSE_ID" = "0" ]; then
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO302'" | tr -d '[:space:]')
fi
if [ -z "$COURSE_ID" ]; then
    COURSE_ID="0"
fi
echo "BIO302 course ID: $COURSE_ID"

# ---------------------------------------------------------------------------
# Look up course module IDs for each activity
# ---------------------------------------------------------------------------

# Activity 1: Page – "Lab Safety and Ethics Module"
PAGE_CMID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm \
    JOIN mdl_page p ON cm.instance=p.id \
    JOIN mdl_modules m ON cm.module=m.id \
    WHERE p.course=${COURSE_ID:-0} \
      AND LOWER(p.name) LIKE '%lab safety%' \
      AND m.name='page' \
    LIMIT 1" | tr -d '[:space:]')
PAGE_CMID="${PAGE_CMID:-0}"
echo "Page cmid: $PAGE_CMID"

# Activity 2: Assignment – "Cell Membrane Transport Lab"
LAB_CMID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm \
    JOIN mdl_assign a ON cm.instance=a.id \
    JOIN mdl_modules m ON cm.module=m.id \
    WHERE a.course=${COURSE_ID:-0} \
      AND LOWER(a.name) LIKE '%membrane transport%' \
      AND m.name='assign' \
    LIMIT 1" | tr -d '[:space:]')
LAB_CMID="${LAB_CMID:-0}"
echo "Lab assignment cmid: $LAB_CMID"

# Activity 3: Quiz – "Molecular Biology Quiz"
QUIZ_CMID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm \
    JOIN mdl_quiz q ON cm.instance=q.id \
    JOIN mdl_modules m ON cm.module=m.id \
    WHERE q.course=${COURSE_ID:-0} \
      AND LOWER(q.name) LIKE '%molecular bio%' \
      AND m.name='quiz' \
    LIMIT 1" | tr -d '[:space:]')
QUIZ_CMID="${QUIZ_CMID:-0}"
echo "Quiz cmid: $QUIZ_CMID"

# Activity 4: Forum – "Research Discussion Forum"
FORUM_CMID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm \
    JOIN mdl_forum f ON cm.instance=f.id \
    JOIN mdl_modules m ON cm.module=m.id \
    WHERE f.course=${COURSE_ID:-0} \
      AND LOWER(f.name) LIKE '%research discussion%' \
      AND m.name='forum' \
    LIMIT 1" | tr -d '[:space:]')
FORUM_CMID="${FORUM_CMID:-0}"
echo "Forum cmid: $FORUM_CMID"

# Activity 5: Assignment – "Final Research Report"
FINAL_CMID=$(moodle_query "SELECT cm.id FROM mdl_course_modules cm \
    JOIN mdl_assign a ON cm.instance=a.id \
    JOIN mdl_modules m ON cm.module=m.id \
    WHERE a.course=${COURSE_ID:-0} \
      AND LOWER(a.name) LIKE '%final research%' \
      AND m.name='assign' \
    LIMIT 1" | tr -d '[:space:]')
FINAL_CMID="${FINAL_CMID:-0}"
echo "Final report cmid: $FINAL_CMID"

# ---------------------------------------------------------------------------
# Read completion settings for each activity from mdl_course_modules
# ---------------------------------------------------------------------------

# Page: completion, completionview
PAGE_COMPLETION_RAW=$(moodle_query "SELECT completion, completionview FROM mdl_course_modules WHERE id=${PAGE_CMID}" | tr '\t' ',')
PAGE_COMPLETION=$(echo "$PAGE_COMPLETION_RAW" | cut -d',' -f1 | tr -d '[:space:]')
PAGE_COMPLETIONVIEW=$(echo "$PAGE_COMPLETION_RAW" | cut -d',' -f2 | tr -d '[:space:]')
PAGE_COMPLETION="${PAGE_COMPLETION:-0}"
PAGE_COMPLETIONVIEW="${PAGE_COMPLETIONVIEW:-0}"
echo "Page completion=$PAGE_COMPLETION view=$PAGE_COMPLETIONVIEW"

# Lab assignment: completion, completionusegrade; also check assign.completionsubmit
LAB_CM_RAW=$(moodle_query "SELECT completion, completionusegrade FROM mdl_course_modules WHERE id=${LAB_CMID}" | tr '\t' ',')
LAB_COMPLETION=$(echo "$LAB_CM_RAW" | cut -d',' -f1 | tr -d '[:space:]')
LAB_COMPLETIONUSEGRADE=$(echo "$LAB_CM_RAW" | cut -d',' -f2 | tr -d '[:space:]')
LAB_COMPLETION="${LAB_COMPLETION:-0}"
LAB_COMPLETIONUSEGRADE="${LAB_COMPLETIONUSEGRADE:-0}"

# Also check assign.completionsubmit (agent may set this via the UI)
LAB_ASSIGN_INSTANCE=$(moodle_query "SELECT instance FROM mdl_course_modules WHERE id=${LAB_CMID}" | tr -d '[:space:]')
LAB_COMPLETIONSUBMIT="0"
if [ -n "$LAB_ASSIGN_INSTANCE" ] && [ "$LAB_ASSIGN_INSTANCE" != "0" ]; then
    LAB_COMPLETIONSUBMIT=$(moodle_query "SELECT completionsubmit FROM mdl_assign WHERE id=${LAB_ASSIGN_INSTANCE}" | tr -d '[:space:]')
    LAB_COMPLETIONSUBMIT="${LAB_COMPLETIONSUBMIT:-0}"
fi
echo "Lab completion=$LAB_COMPLETION usegrade=$LAB_COMPLETIONUSEGRADE completionsubmit=$LAB_COMPLETIONSUBMIT"

# Quiz: completion, completionusegrade, completionpassgrade
QUIZ_CM_RAW=$(moodle_query "SELECT completion, completionusegrade, completionpassgrade FROM mdl_course_modules WHERE id=${QUIZ_CMID}" | tr '\t' ',')
QUIZ_COMPLETION=$(echo "$QUIZ_CM_RAW" | cut -d',' -f1 | tr -d '[:space:]')
QUIZ_COMPLETIONUSEGRADE=$(echo "$QUIZ_CM_RAW" | cut -d',' -f2 | tr -d '[:space:]')
QUIZ_COMPLETIONPASSGRADE=$(echo "$QUIZ_CM_RAW" | cut -d',' -f3 | tr -d '[:space:]')
QUIZ_COMPLETION="${QUIZ_COMPLETION:-0}"
QUIZ_COMPLETIONUSEGRADE="${QUIZ_COMPLETIONUSEGRADE:-0}"
QUIZ_COMPLETIONPASSGRADE="${QUIZ_COMPLETIONPASSGRADE:-0}"
echo "Quiz completion=$QUIZ_COMPLETION usegrade=$QUIZ_COMPLETIONUSEGRADE passgrade=$QUIZ_COMPLETIONPASSGRADE"

# Forum: completion from mdl_course_modules; completionposts from mdl_forum
FORUM_CM_COMPLETION=$(moodle_query "SELECT completion FROM mdl_course_modules WHERE id=${FORUM_CMID}" | tr -d '[:space:]')
FORUM_CM_COMPLETION="${FORUM_CM_COMPLETION:-0}"
FORUM_INSTANCE=$(moodle_query "SELECT instance FROM mdl_course_modules WHERE id=${FORUM_CMID}" | tr -d '[:space:]')
FORUM_COMPLETIONPOSTS="0"
FORUM_COMPLETIONDISCUSSIONS="0"
FORUM_COMPLETIONREPLIES="0"
if [ -n "$FORUM_INSTANCE" ] && [ "$FORUM_INSTANCE" != "0" ]; then
    FORUM_POSTS_RAW=$(moodle_query "SELECT completionposts, completiondiscussions, completionreplies FROM mdl_forum WHERE id=${FORUM_INSTANCE}" | tr '\t' ',')
    FORUM_COMPLETIONPOSTS=$(echo "$FORUM_POSTS_RAW" | cut -d',' -f1 | tr -d '[:space:]')
    FORUM_COMPLETIONDISCUSSIONS=$(echo "$FORUM_POSTS_RAW" | cut -d',' -f2 | tr -d '[:space:]')
    FORUM_COMPLETIONREPLIES=$(echo "$FORUM_POSTS_RAW" | cut -d',' -f3 | tr -d '[:space:]')
fi
FORUM_COMPLETIONPOSTS="${FORUM_COMPLETIONPOSTS:-0}"
FORUM_COMPLETIONDISCUSSIONS="${FORUM_COMPLETIONDISCUSSIONS:-0}"
FORUM_COMPLETIONREPLIES="${FORUM_COMPLETIONREPLIES:-0}"
echo "Forum completion=$FORUM_CM_COMPLETION posts=$FORUM_COMPLETIONPOSTS discussions=$FORUM_COMPLETIONDISCUSSIONS replies=$FORUM_COMPLETIONREPLIES"

# Final report assignment: completion, completionusegrade; also check assign.completionsubmit
FINAL_CM_RAW=$(moodle_query "SELECT completion, completionusegrade FROM mdl_course_modules WHERE id=${FINAL_CMID}" | tr '\t' ',')
FINAL_COMPLETION=$(echo "$FINAL_CM_RAW" | cut -d',' -f1 | tr -d '[:space:]')
FINAL_COMPLETIONUSEGRADE=$(echo "$FINAL_CM_RAW" | cut -d',' -f2 | tr -d '[:space:]')
FINAL_COMPLETION="${FINAL_COMPLETION:-0}"
FINAL_COMPLETIONUSEGRADE="${FINAL_COMPLETIONUSEGRADE:-0}"

FINAL_ASSIGN_INSTANCE=$(moodle_query "SELECT instance FROM mdl_course_modules WHERE id=${FINAL_CMID}" | tr -d '[:space:]')
FINAL_COMPLETIONSUBMIT="0"
if [ -n "$FINAL_ASSIGN_INSTANCE" ] && [ "$FINAL_ASSIGN_INSTANCE" != "0" ]; then
    FINAL_COMPLETIONSUBMIT=$(moodle_query "SELECT completionsubmit FROM mdl_assign WHERE id=${FINAL_ASSIGN_INSTANCE}" | tr -d '[:space:]')
    FINAL_COMPLETIONSUBMIT="${FINAL_COMPLETIONSUBMIT:-0}"
fi
echo "Final completion=$FINAL_COMPLETION usegrade=$FINAL_COMPLETIONUSEGRADE completionsubmit=$FINAL_COMPLETIONSUBMIT"

# ---------------------------------------------------------------------------
# Derive boolean flags for verifier
# ---------------------------------------------------------------------------

# Page: view tracked = completion==2 AND completionview==1
if [ "$PAGE_COMPLETION" = "2" ] && [ "$PAGE_COMPLETIONVIEW" = "1" ]; then
    PAGE_VIEW_TRACKED="true"
else
    PAGE_VIEW_TRACKED="false"
fi

# Lab: submit tracked = completion==2 AND (completionsubmit==1 OR completionusegrade==1)
if [ "$LAB_COMPLETION" = "2" ] && ([ "$LAB_COMPLETIONSUBMIT" = "1" ] || [ "$LAB_COMPLETIONUSEGRADE" = "1" ]); then
    LAB_SUBMIT_TRACKED="true"
else
    LAB_SUBMIT_TRACKED="false"
fi

# Quiz: grade tracked = completion==2 AND completionusegrade==1 AND completionpassgrade==1
if [ "$QUIZ_COMPLETION" = "2" ] && [ "$QUIZ_COMPLETIONUSEGRADE" = "1" ] && [ "$QUIZ_COMPLETIONPASSGRADE" = "1" ]; then
    QUIZ_PASS_REQUIRED="true"
else
    QUIZ_PASS_REQUIRED="false"
fi
if [ "$QUIZ_COMPLETION" = "2" ] && [ "$QUIZ_COMPLETIONUSEGRADE" = "1" ]; then
    QUIZ_GRADE_TRACKED="true"
else
    QUIZ_GRADE_TRACKED="false"
fi

# Forum: post tracked = completion==2 AND (completionposts>=1 OR completiondiscussions>=1 OR completionreplies>=1)
FORUM_POST_TRACKED="false"
if [ "$FORUM_CM_COMPLETION" = "2" ]; then
    if [ "${FORUM_COMPLETIONPOSTS:-0}" -ge 1 ] 2>/dev/null || \
       [ "${FORUM_COMPLETIONDISCUSSIONS:-0}" -ge 1 ] 2>/dev/null || \
       [ "${FORUM_COMPLETIONREPLIES:-0}" -ge 1 ] 2>/dev/null; then
        FORUM_POST_TRACKED="true"
    fi
fi

# Final: submit tracked = completion==2 AND (completionsubmit==1 OR completionusegrade==1)
if [ "$FINAL_COMPLETION" = "2" ] && ([ "$FINAL_COMPLETIONSUBMIT" = "1" ] || [ "$FINAL_COMPLETIONUSEGRADE" = "1" ]); then
    FINAL_SUBMIT_TRACKED="true"
else
    FINAL_SUBMIT_TRACKED="false"
fi

# ---------------------------------------------------------------------------
# Course completion criteria count
# ---------------------------------------------------------------------------
COMPLETION_CRITERIA_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_course_completion_criteria WHERE course=${COURSE_ID:-0}" | tr -d '[:space:]')
COMPLETION_CRITERIA_COUNT="${COMPLETION_CRITERIA_COUNT:-0}"
echo "Course completion criteria count: $COMPLETION_CRITERIA_COUNT"

# ---------------------------------------------------------------------------
# Badge information
# ---------------------------------------------------------------------------
BADGE_DATA=$(moodle_query "SELECT id, name, expireperiod, expiretype FROM mdl_badge WHERE courseid=${COURSE_ID:-0} LIMIT 1")
BADGE_FOUND="false"
BADGE_ID=""
BADGE_NAME=""
BADGE_EXPIREPERIOD="0"
BADGE_EXPIRETYPE="0"
BADGE_HAS_COMPLETION_CRITERIA="false"

if [ -n "$BADGE_DATA" ]; then
    BADGE_FOUND="true"
    BADGE_ID=$(echo "$BADGE_DATA" | cut -f1 | tr -d '[:space:]')
    BADGE_NAME=$(echo "$BADGE_DATA" | cut -f2)
    BADGE_EXPIREPERIOD=$(echo "$BADGE_DATA" | cut -f3 | tr -d '[:space:]')
    BADGE_EXPIRETYPE=$(echo "$BADGE_DATA" | cut -f4 | tr -d '[:space:]')
    BADGE_EXPIREPERIOD="${BADGE_EXPIREPERIOD:-0}"
    BADGE_EXPIRETYPE="${BADGE_EXPIRETYPE:-0}"
    echo "Badge found: id=$BADGE_ID name='$BADGE_NAME' expireperiod=$BADGE_EXPIREPERIOD expiretype=$BADGE_EXPIRETYPE"

    # Check for course completion criterion (criteriatype=8)
    if [ -n "$BADGE_ID" ] && [ "$BADGE_ID" != "0" ]; then
        BADGE_CRITERIA_TYPE=$(moodle_query "SELECT criteriatype FROM mdl_badge_criteria WHERE badgeid=${BADGE_ID} LIMIT 5" 2>/dev/null | tr -d '[:space:]' | tr '\n' ',')
        echo "Badge criteria types: $BADGE_CRITERIA_TYPE"
        if echo "$BADGE_CRITERIA_TYPE" | grep -q "8"; then
            BADGE_HAS_COMPLETION_CRITERIA="true"
        fi
    fi
else
    echo "No badge found for course $COURSE_ID"
fi

# Escape badge name for JSON (replace double-quotes with escaped quotes)
BADGE_NAME_ESC=$(echo "$BADGE_NAME" | sed 's/"/\\"/g')

# ---------------------------------------------------------------------------
# Debug dump of all badges in the course
# ---------------------------------------------------------------------------
echo ""
echo "=== DEBUG: All badges for BIO302 ==="
moodle_query "SELECT id, name, status, courseid, expireperiod, expiretype FROM mdl_badge WHERE courseid=${COURSE_ID:-0}" 2>/dev/null || true
echo "=== END DEBUG ==="
echo ""

echo "=== DEBUG: Course completion criteria ==="
moodle_query "SELECT id, course, criteriatype, moduleinstance FROM mdl_course_completion_criteria WHERE course=${COURSE_ID:-0}" 2>/dev/null || true
echo "=== END DEBUG ==="
echo ""

# ---------------------------------------------------------------------------
# Write result JSON
# ---------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/configure_completion_badge_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "page_cmid": ${PAGE_CMID:-0},
    "lab_cmid": ${LAB_CMID:-0},
    "quiz_cmid": ${QUIZ_CMID:-0},
    "forum_cmid": ${FORUM_CMID:-0},
    "final_cmid": ${FINAL_CMID:-0},
    "page_completion": ${PAGE_COMPLETION:-0},
    "page_completionview": ${PAGE_COMPLETIONVIEW:-0},
    "page_view_tracked": $PAGE_VIEW_TRACKED,
    "lab_completion": ${LAB_COMPLETION:-0},
    "lab_completionsubmit": ${LAB_COMPLETIONSUBMIT:-0},
    "lab_completionusegrade": ${LAB_COMPLETIONUSEGRADE:-0},
    "lab_submit_tracked": $LAB_SUBMIT_TRACKED,
    "quiz_completion": ${QUIZ_COMPLETION:-0},
    "quiz_completionusegrade": ${QUIZ_COMPLETIONUSEGRADE:-0},
    "quiz_completionpassgrade": ${QUIZ_COMPLETIONPASSGRADE:-0},
    "quiz_grade_tracked": $QUIZ_GRADE_TRACKED,
    "quiz_pass_required": $QUIZ_PASS_REQUIRED,
    "forum_completion": ${FORUM_CM_COMPLETION:-0},
    "forum_completionposts": ${FORUM_COMPLETIONPOSTS:-0},
    "forum_completiondiscussions": ${FORUM_COMPLETIONDISCUSSIONS:-0},
    "forum_completionreplies": ${FORUM_COMPLETIONREPLIES:-0},
    "forum_post_tracked": $FORUM_POST_TRACKED,
    "final_completion": ${FINAL_COMPLETION:-0},
    "final_completionsubmit": ${FINAL_COMPLETIONSUBMIT:-0},
    "final_completionusegrade": ${FINAL_COMPLETIONUSEGRADE:-0},
    "final_submit_tracked": $FINAL_SUBMIT_TRACKED,
    "course_completion_criteria_count": ${COMPLETION_CRITERIA_COUNT:-0},
    "badge_found": $BADGE_FOUND,
    "badge_id": "${BADGE_ID:-}",
    "badge_name": "$BADGE_NAME_ESC",
    "badge_expiry_period": ${BADGE_EXPIREPERIOD:-0},
    "badge_expiry_type": ${BADGE_EXPIRETYPE:-0},
    "badge_has_completion_criteria": $BADGE_HAS_COMPLETION_CRITERIA,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_completion_and_badge_result.json

echo ""
cat /tmp/configure_completion_and_badge_result.json
echo ""
echo "=== Export Complete ==="
