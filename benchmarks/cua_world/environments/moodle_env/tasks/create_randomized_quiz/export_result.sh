#!/bin/bash
# Export script for Create Randomized Quiz task

echo "=== Exporting Randomized Quiz Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get PHARM101 Course ID
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='PHARM101'" | tr -d '[:space:]')
echo "Course ID: $COURSE_ID"

# 2. Find the Quiz
# Look for quiz created after task start
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
QUIZ_DATA=$(moodle_query "SELECT id, name, gradepass, attempts, timecreated FROM mdl_quiz WHERE course=$COURSE_ID AND name LIKE '%Interaction Check%' ORDER BY id DESC LIMIT 1")

QUIZ_FOUND="false"
QUIZ_ID=""
QUIZ_NAME=""
GRADEPASS=""
ATTEMPTS=""
CREATED_TIMESTAMP=""

if [ -n "$QUIZ_DATA" ]; then
    QUIZ_FOUND="true"
    QUIZ_ID=$(echo "$QUIZ_DATA" | cut -f1)
    QUIZ_NAME=$(echo "$QUIZ_DATA" | cut -f2)
    GRADEPASS=$(echo "$QUIZ_DATA" | cut -f3)
    ATTEMPTS=$(echo "$QUIZ_DATA" | cut -f4)
    CREATED_TIMESTAMP=$(echo "$QUIZ_DATA" | cut -f5)
    echo "Quiz Found: $QUIZ_NAME (ID: $QUIZ_ID)"
else
    echo "Quiz NOT found."
fi

# 3. Analyze Quiz Slots (The critical part for random questions)
SLOT_COUNT=0
RANDOM_SLOT_COUNT=0
TARGET_CATEGORY_ID=$(cat /tmp/target_category_id 2>/dev/null || echo "0")
CORRECT_CATEGORY_SOURCE="false"

if [ "$QUIZ_FOUND" = "true" ]; then
    # Count total slots
    SLOT_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_quiz_slots WHERE quizid=$QUIZ_ID" | tr -d '[:space:]')
    
    # In Moodle 4.x, random questions are stored via mdl_question_set_references
    # linked to the slot ID.
    # component = 'mod_quiz', questionarea = 'slot', itemid = slot.id
    
    # Check how many slots have a set reference (implies random)
    RANDOM_SLOT_COUNT=$(moodle_query "
        SELECT COUNT(DISTINCT qs.id)
        FROM mdl_quiz_slots qs
        JOIN mdl_question_set_references qsr ON qsr.itemid = qs.id
        WHERE qs.quizid = $QUIZ_ID
        AND qsr.component = 'mod_quiz'
        AND qsr.questionarea = 'slot'
    " | tr -d '[:space:]')
    
    # Check if the random questions are pulling from the correct category
    # The 'filtercondition' column contains JSON like {"cat":"123,456"} or similar
    # We check if our target category ID is present in the filter condition
    CATEGORY_MATCHES=$(moodle_query "
        SELECT COUNT(*)
        FROM mdl_quiz_slots qs
        JOIN mdl_question_set_references qsr ON qsr.itemid = qs.id
        WHERE qs.quizid = $QUIZ_ID
        AND qsr.component = 'mod_quiz'
        AND qsr.questionarea = 'slot'
        AND qsr.filtercondition LIKE '%\"cat\":\"$TARGET_CATEGORY_ID%'
    " | tr -d '[:space:]')
    
    if [ "$CATEGORY_MATCHES" -gt 0 ]; then
        CORRECT_CATEGORY_SOURCE="true"
    fi
fi

# 4. Anti-gaming: Check if quiz was newly created
NEWLY_CREATED="false"
if [ -n "$CREATED_TIMESTAMP" ] && [ "$CREATED_TIMESTAMP" -gt "$TASK_START" ]; then
    NEWLY_CREATED="true"
fi

# Escape JSON strings
QUIZ_NAME_ESC=$(echo "$QUIZ_NAME" | sed 's/"/\\"/g')

# 5. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/random_quiz_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "quiz_found": $QUIZ_FOUND,
    "quiz_name": "$QUIZ_NAME_ESC",
    "course_id": "$COURSE_ID",
    "gradepass": "$GRADEPASS",
    "attempts": "$ATTEMPTS",
    "slot_count": ${SLOT_COUNT:-0},
    "random_slot_count": ${RANDOM_SLOT_COUNT:-0},
    "correct_category_source": $CORRECT_CATEGORY_SOURCE,
    "newly_created": $NEWLY_CREATED,
    "target_category_id": "$TARGET_CATEGORY_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/random_quiz_result.json

echo ""
echo "Export Data:"
cat /tmp/random_quiz_result.json
echo ""
echo "=== Export Complete ==="