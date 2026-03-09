#!/bin/bash
echo "=== Exporting Create Vendor Questionnaire Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record basic info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_questionnaire_count.txt 2>/dev/null || echo "0")

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Query Database for the specific Questionnaire
# We look for a questionnaire created/modified after task start with the correct title
# We fetch ID, Title, Created timestamp
QUESTIONNAIRE_JSON=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id, title, created FROM questionnaires \
     WHERE title LIKE '%Vendor Security Assessment - Tier 1%' \
     AND deleted=0 ORDER BY id DESC LIMIT 1;" 2>/dev/null | \
    while read -r id title created; do
        # If we found a questionnaire, look for its chapters
        echo "{\"id\": \"$id\", \"title\": \"$title\", \"created\": \"$created\", \"chapters\": ["
        
        # Get Chapters for this questionnaire
        FIRST_CHAPTER=true
        docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
            "SELECT id, title FROM chapters WHERE questionnaire_id=$id AND deleted=0;" 2>/dev/null | \
        while read -r cid ctitle; do
            if [ "$FIRST_CHAPTER" = "true" ]; then FIRST_CHAPTER=false; else echo ","; fi
            echo "{\"id\": \"$cid\", \"title\": \"$ctitle\", \"questions\": ["
            
            # Get Questions for this chapter
            FIRST_QUESTION=true
            # Note: Table might be 'questions' or 'questionnaire_questions'. Trying 'questions' first.
            # We assume columns: id, title, type (or similar). 
            # Eramba questions usually have a 'type' column (int or string).
            docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
                "SELECT id, title, type FROM questions WHERE chapter_id=$cid AND deleted=0;" 2>/dev/null | \
            while read -r qid qtitle qtype; do
                if [ "$FIRST_QUESTION" = "true" ]; then FIRST_QUESTION=false; else echo ","; fi
                echo "{\"id\": \"$qid\", \"title\": \"$qtitle\", \"type\": \"$qtype\"}"
            done
            echo "]}" 
        done
        echo "]}"
    done
)

# If query returned nothing, set JSON to null/empty object
if [ -z "$QUESTIONNAIRE_JSON" ]; then
    QUESTIONNAIRE_JSON="null"
fi

# 4. Get final count
FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM questionnaires WHERE deleted=0;" 2>/dev/null || echo "0")

# 5. Construct full result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "questionnaire_data": $QUESTIONNAIRE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json