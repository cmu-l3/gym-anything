#!/bin/bash
echo "=== Exporting setup_inventory_columns result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_REPO_COUNT=$(cat /tmp/initial_inventory_col_count 2>/dev/null || echo "0")
INITIAL_ROW_COUNT=$(cat /tmp/initial_inventory_row_count 2>/dev/null || echo "0")

# Current counts
CURRENT_REPO_COUNT=$(get_repository_count)
CURRENT_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')

# Find the expected inventory
EXPECTED_INVENTORY="Antibody Stock"
REPO_DATA=$(scinote_db_query "SELECT id, name FROM repositories WHERE LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_INVENTORY}')) LIMIT 1;")

REPO_FOUND="false"
REPO_ID=""
REPO_NAME=""

if [ -n "$REPO_DATA" ]; then
    REPO_FOUND="true"
    REPO_ID=$(echo "$REPO_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
    REPO_NAME=$(echo "$REPO_DATA" | cut -d'|' -f2 | xargs)
fi

# Find custom columns (exclude the default 'Name' column which is implicit)
COLUMNS_JSON="[]"
CATALOG_COL_ID=""
if [ "$REPO_FOUND" = "true" ] && [ -n "$REPO_ID" ]; then
    COLUMNS_DATA=$(scinote_db_query "SELECT id, name, data_type FROM repository_columns WHERE repository_id=${REPO_ID} ORDER BY id;")
    COLUMNS_JSON="["
    COL_FIRST=true
    while IFS='|' read -r col_id col_name col_type; do
        [ -z "$col_id" ] && continue
        col_name_clean=$(echo "$col_name" | sed 's/"/\\"/g' | xargs)
        col_id_clean=$(echo "$col_id" | tr -d '[:space:]')
        col_type_clean=$(echo "$col_type" | tr -d '[:space:]')

        if [ "$COL_FIRST" = true ]; then
            COL_FIRST=false
        else
            COLUMNS_JSON="${COLUMNS_JSON}, "
        fi
        COLUMNS_JSON="${COLUMNS_JSON}{\"id\": \"${col_id_clean}\", \"name\": \"${col_name_clean}\", \"data_type\": ${col_type_clean:-0}}"

        # Check if this is the Catalog Number column
        if echo "$col_name_clean" | grep -qi "catalog"; then
            CATALOG_COL_ID="$col_id_clean"
        fi
    done <<< "$COLUMNS_DATA"
    COLUMNS_JSON="${COLUMNS_JSON}]"
fi

# Find items (rows) in this inventory
ITEMS_JSON="[]"
if [ "$REPO_FOUND" = "true" ] && [ -n "$REPO_ID" ]; then
    ROWS_DATA=$(scinote_db_query "SELECT id, name FROM repository_rows WHERE repository_id=${REPO_ID} ORDER BY id;")
    ITEMS_JSON="["
    ITEM_FIRST=true
    while IFS='|' read -r row_id row_name; do
        [ -z "$row_id" ] && continue
        row_name_clean=$(echo "$row_name" | sed 's/"/\\"/g' | xargs)
        row_id_clean=$(echo "$row_id" | tr -d '[:space:]')

        # Get catalog number cell value if column exists
        CATALOG_VALUE=""
        if [ -n "$CATALOG_COL_ID" ]; then
            CATALOG_VALUE=$(scinote_db_query "SELECT rtv.data FROM repository_cells rc JOIN repository_text_values rtv ON rc.value_type='RepositoryTextValue' AND rc.value_id=rtv.id WHERE rc.repository_row_id=${row_id_clean} AND rc.repository_column_id=${CATALOG_COL_ID} LIMIT 1;" 2>/dev/null | head -1 | xargs)
        fi
        CATALOG_VALUE_CLEAN=$(echo "$CATALOG_VALUE" | sed 's/"/\\"/g')

        if [ "$ITEM_FIRST" = true ]; then
            ITEM_FIRST=false
        else
            ITEMS_JSON="${ITEMS_JSON}, "
        fi
        ITEMS_JSON="${ITEMS_JSON}{\"id\": \"${row_id_clean}\", \"name\": \"${row_name_clean}\", \"catalog_number\": \"${CATALOG_VALUE_CLEAN}\"}"
    done <<< "$ROWS_DATA"
    ITEMS_JSON="${ITEMS_JSON}]"
fi

REPO_NAME_ESCAPED=$(json_escape "$REPO_NAME")

RESULT_JSON=$(cat << EOF
{
    "initial_repository_count": ${INITIAL_REPO_COUNT:-0},
    "current_repository_count": ${CURRENT_REPO_COUNT:-0},
    "initial_row_count": ${INITIAL_ROW_COUNT:-0},
    "current_row_count": ${CURRENT_ROW_COUNT:-0},
    "repository_found": ${REPO_FOUND},
    "repository": {
        "id": "${REPO_ID}",
        "name": "${REPO_NAME_ESCAPED}"
    },
    "columns": ${COLUMNS_JSON},
    "items": ${ITEMS_JSON},
    "catalog_column_id": "${CATALOG_COL_ID}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/setup_inventory_columns_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/setup_inventory_columns_result.json"
cat /tmp/setup_inventory_columns_result.json
echo "=== Export complete ==="
