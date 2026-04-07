#!/bin/bash
echo "=== Exporting document_reagent_prep_workflow result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

INITIAL_STOCK_COUNT=$(cat /tmp/initial_stock_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Search for the expected task
TASK_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE LOWER(TRIM(name)) = LOWER(TRIM('Prepare 10x PBS Stock')) LIMIT 1;" | tr -d '[:space:]')
TASK_ID=${TASK_ID:-0}

TASK_FOUND="false"
if [ "$TASK_ID" != "0" ]; then
    TASK_FOUND="true"
fi

# 2. Extract Result Text attached to the task
# Checks results table (name/data) and texts table just in case
RESULT_TEXT=$(scinote_db_query "SELECT COALESCE(name,'') || ' ' || COALESCE(data,'') FROM results WHERE my_module_id=${TASK_ID};" 2>/dev/null | tr '\n' ' ')
if [ -z "$RESULT_TEXT" ] || [ "$RESULT_TEXT" = " " ]; then
    # Fallback to module description if they put it there instead
    RESULT_TEXT=$(scinote_db_query "SELECT COALESCE(description,'') FROM my_modules WHERE id=${TASK_ID};" 2>/dev/null | tr '\n' ' ')
fi

# Escape text for JSON
RESULT_TEXT_ESCAPED=$(json_escape "$RESULT_TEXT")

# 3. Check for final output item in 'Stock Solutions'
STOCK_REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='Stock Solutions' LIMIT 1;" | tr -d '[:space:]')
STOCK_REPO_ID=${STOCK_REPO_ID:-0}

OUTPUT_ITEM_FOUND="false"
OUTPUT_ITEM_NAME=""
CURRENT_STOCK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${STOCK_REPO_ID};" | tr -d '[:space:]')
CURRENT_STOCK_COUNT=${CURRENT_STOCK_COUNT:-0}

if [ "$STOCK_REPO_ID" != "0" ]; then
    ITEM_DATA=$(scinote_db_query "SELECT id, name FROM repository_rows WHERE repository_id=${STOCK_REPO_ID} AND LOWER(name) LIKE '%10x pbs%' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null)
    if [ -n "$ITEM_DATA" ]; then
        OUTPUT_ITEM_FOUND="true"
        OUTPUT_ITEM_NAME=$(echo "$ITEM_DATA" | cut -d'|' -f2 | xargs)
    fi
fi
OUTPUT_ITEM_NAME_ESCAPED=$(json_escape "$OUTPUT_ITEM_NAME")

# 4. Check for ingredient assignments
# We check common assignment tables or activity logs.
ASSIGNED_INGREDIENTS="[]"
ASSIGNED_COUNT=0

if [ "$TASK_ID" != "0" ]; then
    # Try multiple table structures (assigned_repository_rows or module_repository_rows)
    ASSIGN_IDS=$(scinote_db_query "SELECT repository_row_id FROM assigned_repository_rows WHERE assignable_id=${TASK_ID} AND assignable_type='MyModule';" 2>/dev/null)
    if [ -z "$ASSIGN_IDS" ]; then
        ASSIGN_IDS=$(scinote_db_query "SELECT repository_row_id FROM my_module_repository_rows WHERE my_module_id=${TASK_ID};" 2>/dev/null)
    fi
    
    if [ -n "$ASSIGN_IDS" ]; then
        ASSIGNED_INGREDIENTS="["
        FIRST=true
        while IFS= read -r rr_id; do
            rr_id=$(echo "$rr_id" | tr -d '[:space:]')
            [ -z "$rr_id" ] && continue
            
            RR_NAME=$(scinote_db_query "SELECT name FROM repository_rows WHERE id=${rr_id};" | tr -d '\n')
            RR_NAME_CLEAN=$(json_escape "$RR_NAME")
            
            if [ "$FIRST" = true ]; then
                ASSIGNED_INGREDIENTS="${ASSIGNED_INGREDIENTS}\"${RR_NAME_CLEAN}\""
                FIRST=false
            else
                ASSIGNED_INGREDIENTS="${ASSIGNED_INGREDIENTS}, \"${RR_NAME_CLEAN}\""
            fi
            ASSIGNED_COUNT=$((ASSIGNED_COUNT + 1))
        done <<< "$ASSIGN_IDS"
        ASSIGNED_INGREDIENTS="${ASSIGNED_INGREDIENTS}]"
    fi
fi

# Create result JSON
RESULT_JSON=$(cat << EOF
{
    "task_start_time": ${TASK_START_TIME},
    "task_found": ${TASK_FOUND},
    "task_id": "${TASK_ID}",
    "result_text": "${RESULT_TEXT_ESCAPED}",
    "initial_stock_count": ${INITIAL_STOCK_COUNT:-0},
    "current_stock_count": ${CURRENT_STOCK_COUNT:-0},
    "output_item_found": ${OUTPUT_ITEM_FOUND},
    "output_item_name": "${OUTPUT_ITEM_NAME_ESCAPED}",
    "assigned_count": ${ASSIGNED_COUNT},
    "assigned_ingredients": ${ASSIGNED_INGREDIENTS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/reagent_prep_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/reagent_prep_result.json"
cat /tmp/reagent_prep_result.json
echo "=== Export complete ==="