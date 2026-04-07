#!/bin/bash
# Export script for Import Question Bank task

echo "=== Exporting Import Question Bank Result ==="

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

# Get BIO101 course ID and Context ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
# Context Level 50 = Course. We need the context ID for BIO101 to check category placement.
COURSE_CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')

echo "BIO101 ID: $COURSE_ID, Context ID: $COURSE_CONTEXT_ID"

# 1. Check for Category "Pharmacology Module 3"
# We look for the category specifically in the course context
CATEGORY_DATA=$(moodle_query "SELECT id, name, contextid, timecreated FROM mdl_question_categories WHERE name LIKE '%Pharmacology Module 3%' AND contextid=$COURSE_CONTEXT_ID ORDER BY id DESC LIMIT 1")

CAT_FOUND="false"
CAT_ID="0"
CAT_NAME=""
CAT_CONTEXT_ID="0"
CAT_TIMECREATED="0"

if [ -n "$CATEGORY_DATA" ]; then
    CAT_FOUND="true"
    CAT_ID=$(echo "$CATEGORY_DATA" | cut -f1 | tr -d '[:space:]')
    CAT_NAME=$(echo "$CATEGORY_DATA" | cut -f2)
    CAT_CONTEXT_ID=$(echo "$CATEGORY_DATA" | cut -f3 | tr -d '[:space:]')
    CAT_TIMECREATED=$(echo "$CATEGORY_DATA" | cut -f4 | tr -d '[:space:]')
    echo "Category found: ID=$CAT_ID, Name='$CAT_NAME', Context=$CAT_CONTEXT_ID"
else
    echo "Category 'Pharmacology Module 3' NOT found in BIO101 context."
    # Fallback: Check if it exists globally or in other contexts (for partial credit feedback)
    ANY_CAT=$(moodle_query "SELECT id, contextid FROM mdl_question_categories WHERE name LIKE '%Pharmacology Module 3%' LIMIT 1")
    if [ -n "$ANY_CAT" ]; then
        echo "Note: Category found in wrong context/course."
    fi
fi

# 2. Count questions in this category
# Moodle 4.x structure: mdl_question -> mdl_question_versions -> mdl_question_bank_entries -> mdl_question_categories
QUESTION_COUNT="0"
QUESTIONS_JSON="[]"

if [ "$CAT_FOUND" = "true" ]; then
    # Count valid questions
    QUESTION_COUNT=$(moodle_query "
        SELECT COUNT(DISTINCT q.id)
        FROM mdl_question q
        JOIN mdl_question_versions qv ON q.id = qv.questionid
        JOIN mdl_question_bank_entries qbe ON qv.questionbankentryid = qbe.id
        WHERE qbe.questioncategoryid = $CAT_ID
        AND qv.version = (
            SELECT MAX(v.version)
            FROM mdl_question_versions v
            WHERE v.questionbankentryid = qbe.id
        )
    " | tr -d '[:space:]')
    
    # Get details of questions (name, qtype)
    # Using python to format as JSON array since raw SQL to JSON is hard in bash
    QUESTIONS_RAW=$(moodle_query "
        SELECT q.name, q.qtype, q.id
        FROM mdl_question q
        JOIN mdl_question_versions qv ON q.id = qv.questionid
        JOIN mdl_question_bank_entries qbe ON qv.questionbankentryid = qbe.id
        WHERE qbe.questioncategoryid = $CAT_ID
        AND qv.version = (
            SELECT MAX(v.version)
            FROM mdl_question_versions v
            WHERE v.questionbankentryid = qbe.id
        )
    ")
    
    # Simple parsing to JSON array of objects
    if [ -n "$QUESTIONS_RAW" ]; then
        # Create a temp python script to format the output
        cat > /tmp/format_questions.py << PYEOF
import json
import sys

lines = sys.stdin.readlines()
questions = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 3:
        questions.append({
            "name": parts[0],
            "qtype": parts[1],
            "id": parts[2]
        })
print(json.dumps(questions))
PYEOF
        QUESTIONS_JSON=$(echo "$QUESTIONS_RAW" | python3 /tmp/format_questions.py)
    fi
fi

echo "Questions found in category: $QUESTION_COUNT"

# 3. Check for specific answers (Spot check)
# Check Warfarin question answer
WARFARIN_ANSWER_CHECK="false"
HEPARIN_ANSWER_CHECK="false"

# Helper to find question ID by name
get_qid_by_name() {
    local qname="$1"
    # Search in all questions, not just the category (in case import worked but cat failed)
    moodle_query "SELECT id FROM mdl_question WHERE name LIKE '%$qname%' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]'
}

WARFARIN_QID=$(get_qid_by_name "Warfarin Antidote")
if [ -n "$WARFARIN_QID" ]; then
    # Check if correct answer (fraction = 1.0) contains Vitamin K
    ANS=$(moodle_query "SELECT answer FROM mdl_question_answers WHERE question=$WARFARIN_QID AND fraction > 0.9" | grep -i "Vitamin K")
    if [ -n "$ANS" ]; then
        WARFARIN_ANSWER_CHECK="true"
        echo "Warfarin answer verification: PASS"
    fi
fi

HEPARIN_QID=$(get_qid_by_name "Heparin Monitoring")
if [ -n "$HEPARIN_QID" ]; then
    # Check if correct answer contains aPTT
    ANS=$(moodle_query "SELECT answer FROM mdl_question_answers WHERE question=$HEPARIN_QID AND fraction > 0.9" | grep -i "aPTT")
    if [ -n "$ANS" ]; then
        HEPARIN_ANSWER_CHECK="true"
        echo "Heparin answer verification: PASS"
    fi
fi

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# Escape for JSON
CAT_NAME_ESC=$(echo "$CAT_NAME" | sed 's/"/\\"/g')

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/import_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "course_context_id": ${COURSE_CONTEXT_ID:-0},
    "category_found": $CAT_FOUND,
    "category_id": "${CAT_ID}",
    "category_name": "${CAT_NAME_ESC}",
    "category_context_id": "${CAT_CONTEXT_ID}",
    "category_timecreated": ${CAT_TIMECREATED:-0},
    "question_count": ${QUESTION_COUNT:-0},
    "questions": $QUESTIONS_JSON,
    "warfarin_check": $WARFARIN_ANSWER_CHECK,
    "heparin_check": $HEPARIN_ANSWER_CHECK,
    "task_start_time": $TASK_START,
    "export_time": $EXPORT_TIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/import_question_bank_result.json

echo ""
echo "=== Export Complete ==="