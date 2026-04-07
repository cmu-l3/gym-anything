#!/bin/bash
echo "=== Exporting generate_serial_dilution_standards result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve initial counts
INITIAL_REPO_COUNT=$(cat /tmp/initial_repository_count 2>/dev/null || echo "0")
INITIAL_ROW_COUNT=$(cat /tmp/initial_repository_row_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_REPO_COUNT=$(get_repository_count)
CURRENT_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')

# Search for the expected inventory
EXPECTED_INVENTORY="BCA Assay Standards"
REPO_DATA=$(scinote_db_query "SELECT id, name, created_at FROM repositories WHERE LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_INVENTORY}')) ORDER BY created_at DESC LIMIT 1;")

REPO_FOUND="false"
REPO_ID=""
REPO_NAME=""
REPO_CREATED=""
ITEM_COUNT=0
ITEMS_JSON="[]"

if [ -n "$REPO_DATA" ]; then
    REPO_FOUND="true"
    REPO_ID=$(echo "$REPO_DATA" | cut -d'|' -f1)
    REPO_NAME=$(echo "$REPO_DATA" | cut -d'|' -f2)
    REPO_CREATED=$(echo "$REPO_DATA" | cut -d'|' -f3)

    # Count items in this specific inventory
    ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    
    # Get all item names in this inventory
    ITEMS_DATA=$(scinote_db_query "SELECT name FROM repository_rows WHERE repository_id=${REPO_ID} ORDER BY name;")
    
    if [ -n "$ITEMS_DATA" ]; then
        ITEMS_JSON="["
        FIRST=true
        while IFS= read -r item_name; do
            [ -z "$item_name" ] && continue
            item_name_clean=$(echo "$item_name" | sed 's/"/\\"/g' | xargs)
            
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                ITEMS_JSON="${ITEMS_JSON}, "
            fi
            ITEMS_JSON="${ITEMS_JSON}\"${item_name_clean}\""
        done <<< "$ITEMS_DATA"
        ITEMS_JSON="${ITEMS_JSON}]"
    fi
fi

REPO_NAME_ESCAPED=$(json_escape "$REPO_NAME")

# Create JSON payload
RESULT_JSON=$(cat << EOF
{
    "initial_repository_count": ${INITIAL_REPO_COUNT:-0},
    "current_repository_count": ${CURRENT_REPO_COUNT:-0},
    "initial_row_count": ${INITIAL_ROW_COUNT:-0},
    "current_row_count": ${CURRENT_ROW_COUNT:-0},
    "repository_found": ${REPO_FOUND},
    "repository": {
        "id": "${REPO_ID}",
        "name": "${REPO_NAME_ESCAPED}",
        "created_at": "${REPO_CREATED}"
    },
    "item_count": ${ITEM_COUNT:-0},
    "items": ${ITEMS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

# Safely write the results output
safe_write_json "/tmp/serial_dilution_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/serial_dilution_result.json"
cat /tmp/serial_dilution_result.json
echo "=== Export complete ==="