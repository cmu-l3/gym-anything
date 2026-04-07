#!/bin/bash
echo "=== Exporting tag_tasks_via_global_search result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

# Read target IDs generated during setup
TARGET_IDS=$(cat /tmp/target_task_ids.txt 2>/dev/null || echo "")
IFS=',' read -r T1 T2 T3 <<< "$TARGET_IDS"

# Get tag ID for "QA Review"
TAG_ID=$(scinote_db_query "SELECT id FROM tags WHERE LOWER(name)='qa review' LIMIT 1;" | tr -d '[:space:]')

TAG_EXISTS="false"
TARGETS_TAGGED=0
NOISE_TAGGED=0
ALL_TAGGED_JSON="[]"
FIRST_ASSIGNMENT_TIME=0

if [ -n "$TAG_ID" ]; then
    TAG_EXISTS="true"
    
    # Get all my_module_ids associated with this tag
    TAGGED_TASKS=$(scinote_db_query "SELECT my_module_id FROM my_module_tags WHERE tag_id=${TAG_ID};")
    
    # Check the first time this tag was assigned (anti-gaming)
    FIRST_ASSIGNMENT_TIME=$(scinote_db_query "SELECT extract(epoch from min(created_at)) FROM my_module_tags WHERE tag_id=${TAG_ID};" | cut -d'.' -f1)
    FIRST_ASSIGNMENT_TIME=${FIRST_ASSIGNMENT_TIME:-0}
    
    ALL_TAGGED_JSON="["
    FIRST=true
    
    while IFS= read -r tid; do
        tid_clean=$(echo "$tid" | tr -d '[:space:]')
        [ -z "$tid_clean" ] && continue
        
        # Check if the tagged task is one of our designated targets
        if [ "$tid_clean" = "$T1" ] || [ "$tid_clean" = "$T2" ] || [ "$tid_clean" = "$T3" ]; then
            TARGETS_TAGGED=$((TARGETS_TAGGED + 1))
        else
            NOISE_TAGGED=$((NOISE_TAGGED + 1))
        fi
        
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            ALL_TAGGED_JSON="${ALL_TAGGED_JSON},"
        fi
        ALL_TAGGED_JSON="${ALL_TAGGED_JSON}${tid_clean}"
    done <<< "$TAGGED_TASKS"
    ALL_TAGGED_JSON="${ALL_TAGGED_JSON}]"
fi

RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tag_exists": $TAG_EXISTS,
    "targets_tagged_count": $TARGETS_TAGGED,
    "noise_tagged_count": $NOISE_TAGGED,
    "tagged_task_ids": $ALL_TAGGED_JSON,
    "target_ids": ["$T1", "$T2", "$T3"],
    "first_assignment_time": $FIRST_ASSIGNMENT_TIME,
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/tag_tasks_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/tag_tasks_result.json"
cat /tmp/tag_tasks_result.json
echo "=== Export complete ==="