#!/bin/bash
# Export script for Build Question Bank and Quiz task

echo "=== Exporting Build Question Bank and Quiz Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils.sh did not provide them
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

# -------------------------------------------------------------------
# Resolve course and context IDs
# -------------------------------------------------------------------
COURSE_ID=$(cat /tmp/math201_course_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$COURSE_ID" ]; then
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='MATH201'" | tr -d '[:space:]')
fi
COURSE_ID=${COURSE_ID:-0}
echo "MATH201 Course ID: $COURSE_ID"

CONTEXT_ID=$(cat /tmp/math201_context_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$CONTEXT_ID" ] && [ "$COURSE_ID" != "0" ]; then
    CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE instanceid=$COURSE_ID AND contextlevel=50" | tr -d '[:space:]')
fi
CONTEXT_ID=${CONTEXT_ID:-0}
echo "MATH201 Context ID: $CONTEXT_ID"

# -------------------------------------------------------------------
# Locate question bank categories
# -------------------------------------------------------------------
PROB_CAT_ID=$(cat /tmp/math201_prob_cat_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$PROB_CAT_ID" ] || [ "$PROB_CAT_ID" = "0" ]; then
    PROB_CAT_ID=$(moodle_query "SELECT id FROM mdl_question_categories WHERE contextid=$CONTEXT_ID AND LOWER(name) LIKE '%probability basics%' LIMIT 1" | tr -d '[:space:]')
fi
PROB_CAT_ID=${PROB_CAT_ID:-0}

STAT_CAT_ID=$(cat /tmp/math201_stat_cat_id 2>/dev/null | tr -d '[:space:]')
if [ -z "$STAT_CAT_ID" ] || [ "$STAT_CAT_ID" = "0" ]; then
    # Try two different name fragments for robustness
    STAT_CAT_ID=$(moodle_query "SELECT id FROM mdl_question_categories WHERE contextid=$CONTEXT_ID AND (LOWER(name) LIKE '%descriptive stat%' OR LOWER(name) LIKE '%descriptive%statistics%') LIMIT 1" | tr -d '[:space:]')
fi
STAT_CAT_ID=${STAT_CAT_ID:-0}

echo "Probability Basics category ID: $PROB_CAT_ID"
echo "Descriptive Statistics category ID: $STAT_CAT_ID"

PROB_CAT_FOUND="false"
STAT_CAT_FOUND="false"
[ "$PROB_CAT_ID" != "0" ] && [ -n "$PROB_CAT_ID" ] && PROB_CAT_FOUND="true"
[ "$STAT_CAT_ID" != "0" ] && [ -n "$STAT_CAT_ID" ] && STAT_CAT_FOUND="true"

# -------------------------------------------------------------------
# Count and classify questions in each category
# -------------------------------------------------------------------

# Probability Basics — total non-random questions
PROB_QUESTION_COUNT="0"
PROB_MC_COUNT="0"
if [ "$PROB_CAT_ID" != "0" ]; then
    PROB_QUESTION_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_question WHERE category=$PROB_CAT_ID AND qtype != 'random'" | tr -d '[:space:]')
    PROB_MC_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_question WHERE category=$PROB_CAT_ID AND qtype='multichoice'" | tr -d '[:space:]')
fi
PROB_QUESTION_COUNT=${PROB_QUESTION_COUNT:-0}
PROB_MC_COUNT=${PROB_MC_COUNT:-0}
echo "Probability Basics: total=${PROB_QUESTION_COUNT}, multichoice=${PROB_MC_COUNT}"

# Descriptive Statistics — total non-random questions
STAT_QUESTION_COUNT="0"
STAT_TF_COUNT="0"
if [ "$STAT_CAT_ID" != "0" ]; then
    STAT_QUESTION_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_question WHERE category=$STAT_CAT_ID AND qtype != 'random'" | tr -d '[:space:]')
    STAT_TF_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_question WHERE category=$STAT_CAT_ID AND qtype='truefalse'" | tr -d '[:space:]')
fi
STAT_QUESTION_COUNT=${STAT_QUESTION_COUNT:-0}
STAT_TF_COUNT=${STAT_TF_COUNT:-0}
echo "Descriptive Statistics: total=${STAT_QUESTION_COUNT}, truefalse=${STAT_TF_COUNT}"

# -------------------------------------------------------------------
# Locate the quiz "MATH201 Mid-Term Examination"
# -------------------------------------------------------------------
QUIZ_FOUND="false"
QUIZ_ID=""
QUIZ_NAME=""
QUIZ_TIMELIMIT="0"
QUIZ_ATTEMPTS="0"
QUIZ_SHUFFLE="0"
QUIZ_TOTAL_SLOTS="0"
RANDOM_SLOT_COUNT="0"
QUIZ_GRADE_PASS="0"

if [ "$COURSE_ID" != "0" ]; then
    QUIZ_DATA=$(moodle_query "SELECT id, name, timelimit, attempts, shuffleanswers FROM mdl_quiz WHERE course=$COURSE_ID AND LOWER(name) LIKE '%mid%' AND LOWER(name) LIKE '%term%' ORDER BY id DESC LIMIT 1")

    if [ -n "$QUIZ_DATA" ]; then
        QUIZ_FOUND="true"
        QUIZ_ID=$(echo "$QUIZ_DATA" | cut -f1 | tr -d '[:space:]')
        QUIZ_NAME=$(echo "$QUIZ_DATA" | cut -f2)
        QUIZ_TIMELIMIT=$(echo "$QUIZ_DATA" | cut -f3 | tr -d '[:space:]')
        QUIZ_ATTEMPTS=$(echo "$QUIZ_DATA" | cut -f4 | tr -d '[:space:]')
        QUIZ_SHUFFLE=$(echo "$QUIZ_DATA" | cut -f5 | tr -d '[:space:]')
        echo "Quiz found: ID=$QUIZ_ID, Name='$QUIZ_NAME'"
        echo "  timelimit=$QUIZ_TIMELIMIT, attempts=$QUIZ_ATTEMPTS, shuffleanswers=$QUIZ_SHUFFLE"
    else
        echo "Target quiz NOT found in MATH201 (searched LOWER(name) LIKE '%mid%' AND '%term%')"
    fi
fi

# Quiz grade to pass (from gradebook)
if [ -n "$QUIZ_ID" ] && [ "$QUIZ_ID" != "" ]; then
    QUIZ_GRADE_PASS=$(moodle_query "SELECT gradepass FROM mdl_grade_items WHERE itemtype='mod' AND itemmodule='quiz' AND iteminstance=$QUIZ_ID LIMIT 1" | tr -d '[:space:]')
    QUIZ_GRADE_PASS=${QUIZ_GRADE_PASS:-0}
    echo "Quiz grade to pass: $QUIZ_GRADE_PASS"

    # Total question slots in the quiz
    QUIZ_TOTAL_SLOTS=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_slots WHERE quizid=$QUIZ_ID" | tr -d '[:space:]')
    QUIZ_TOTAL_SLOTS=${QUIZ_TOTAL_SLOTS:-0}
    echo "Quiz total slots: $QUIZ_TOTAL_SLOTS"

    # Count random-type question slots (Moodle stores random questions as qtype='random' in mdl_question)
    RANDOM_SLOT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_slots qs WHERE qs.quizid=$QUIZ_ID AND qs.questionid IN (SELECT id FROM mdl_question WHERE qtype='random')" 2>/dev/null | tr -d '[:space:]')
    RANDOM_SLOT_COUNT=${RANDOM_SLOT_COUNT:-0}
    echo "Random question slots: $RANDOM_SLOT_COUNT"

    # Alternative detection: Moodle 4.x may use mdl_quiz_slots with no questionid but
    # with a reference in mdl_quiz_random_question_set or mdl_question_set_references.
    # Count slots where questionid IS NULL or 0 (random placeholder approach).
    if [ "$RANDOM_SLOT_COUNT" = "0" ]; then
        RANDOM_SLOT_COUNT_ALT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_slots WHERE quizid=$QUIZ_ID AND (questionid IS NULL OR questionid=0)" 2>/dev/null | tr -d '[:space:]')
        RANDOM_SLOT_COUNT_ALT=${RANDOM_SLOT_COUNT_ALT:-0}
        echo "Random slots (alternative NULL check): $RANDOM_SLOT_COUNT_ALT"
        # Use the larger of the two counts
        if [ "${RANDOM_SLOT_COUNT_ALT:-0}" -gt "${RANDOM_SLOT_COUNT:-0}" ] 2>/dev/null; then
            RANDOM_SLOT_COUNT="$RANDOM_SLOT_COUNT_ALT"
        fi
    fi

    # Check whether both categories appear in random draws
    # Approach: look for 'random' questions in mdl_question whose category matches our bank categories
    PROB_RANDOM_COUNT="0"
    STAT_RANDOM_COUNT="0"
    if [ "$PROB_CAT_ID" != "0" ]; then
        PROB_RANDOM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_question WHERE qtype='random' AND category=$PROB_CAT_ID" 2>/dev/null | tr -d '[:space:]')
        PROB_RANDOM_COUNT=${PROB_RANDOM_COUNT:-0}
    fi
    if [ "$STAT_CAT_ID" != "0" ]; then
        STAT_RANDOM_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_question WHERE qtype='random' AND category=$STAT_CAT_ID" 2>/dev/null | tr -d '[:space:]')
        STAT_RANDOM_COUNT=${STAT_RANDOM_COUNT:-0}
    fi
    echo "Random question placeholders in Probability Basics: $PROB_RANDOM_COUNT"
    echo "Random question placeholders in Descriptive Statistics: $STAT_RANDOM_COUNT"
fi

QUIZ_TIMELIMIT=${QUIZ_TIMELIMIT:-0}
QUIZ_ATTEMPTS=${QUIZ_ATTEMPTS:-0}
QUIZ_SHUFFLE=${QUIZ_SHUFFLE:-0}
QUIZ_GRADE_PASS=${QUIZ_GRADE_PASS:-0}

# Escape the quiz name for JSON
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "$s"
}
QUIZ_NAME_ESC=$(json_escape "$QUIZ_NAME")

# -------------------------------------------------------------------
# Write result JSON
# -------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/question_bank_quiz_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "context_id": ${CONTEXT_ID:-0},
    "prob_cat_found": $PROB_CAT_FOUND,
    "stat_cat_found": $STAT_CAT_FOUND,
    "prob_cat_id": ${PROB_CAT_ID:-0},
    "stat_cat_id": ${STAT_CAT_ID:-0},
    "prob_question_count": ${PROB_QUESTION_COUNT:-0},
    "stat_question_count": ${STAT_QUESTION_COUNT:-0},
    "prob_mc_count": ${PROB_MC_COUNT:-0},
    "stat_tf_count": ${STAT_TF_COUNT:-0},
    "quiz_found": $QUIZ_FOUND,
    "quiz_id": "${QUIZ_ID:-}",
    "quiz_name": "$QUIZ_NAME_ESC",
    "quiz_timelimit_sec": ${QUIZ_TIMELIMIT:-0},
    "quiz_attempts": ${QUIZ_ATTEMPTS:-0},
    "quiz_shuffle": ${QUIZ_SHUFFLE:-0},
    "quiz_grade_pass": ${QUIZ_GRADE_PASS:-0},
    "quiz_total_slots": ${QUIZ_TOTAL_SLOTS:-0},
    "random_slot_count": ${RANDOM_SLOT_COUNT:-0},
    "prob_random_count": ${PROB_RANDOM_COUNT:-0},
    "stat_random_count": ${STAT_RANDOM_COUNT:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/build_question_bank_and_quiz_result.json

echo ""
cat /tmp/build_question_bank_and_quiz_result.json
echo ""
echo "=== Export Complete ==="
