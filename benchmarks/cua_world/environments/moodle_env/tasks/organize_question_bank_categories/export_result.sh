#!/bin/bash
# Export script for Organize Question Bank task

echo "=== Exporting Organize Question Bank Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

COURSE_ID=$(cat /tmp/chem101_course_id 2>/dev/null || echo "0")
DEFAULT_CAT_ID=$(cat /tmp/default_cat_id 2>/dev/null || echo "0")

# 1. Get current structure of categories in this course
echo "Fetching category structure..."
# Moodle 4.x: Categories are linked to context.
# We need categories where contextid matches the course context.
CATS_JSON=$(moodle_query_headers "
SELECT qc.id, qc.name, qc.parent
FROM mdl_question_categories qc
JOIN mdl_context ctx ON qc.contextid = ctx.id
WHERE ctx.instanceid = $COURSE_ID AND ctx.contextlevel = 50
" 2>/dev/null | python3 -c '
import sys, csv, json
reader = csv.DictReader(sys.stdin, delimiter="\t")
print(json.dumps(list(reader)))
')

# 2. Get location of specific questions
# Moodle 4.x: Question -> Version -> Bank Entry -> Category
echo "Fetching question locations..."
QUESTIONS_JSON=$(moodle_query_headers "
SELECT q.name as question_name, qc.id as category_id, qc.name as category_name
FROM mdl_question q
JOIN mdl_question_versions qv ON qv.questionid = q.id
JOIN mdl_question_bank_entries qbe ON qbe.id = qv.questionbankentryid
JOIN mdl_question_categories qc ON qc.id = qbe.questioncategoryid
JOIN mdl_context ctx ON qc.contextid = ctx.id
WHERE (q.name LIKE 'Atom_%' OR q.name LIKE 'Bond_%')
AND ctx.instanceid = $COURSE_ID
" 2>/dev/null | python3 -c '
import sys, csv, json
reader = csv.DictReader(sys.stdin, delimiter="\t")
print(json.dumps(list(reader)))
')

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/organize_qb_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": "$COURSE_ID",
    "default_cat_id": "$DEFAULT_CAT_ID",
    "categories": $CATS_JSON,
    "questions": $QUESTIONS_JSON,
    "export_timestamp": $(date +%s)
}
EOF

# Move to safe location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="