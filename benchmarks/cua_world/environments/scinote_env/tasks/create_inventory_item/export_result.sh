#!/bin/bash
echo "=== Exporting create_inventory_item result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

INITIAL_REPO_COUNT=$(cat /tmp/initial_repository_count 2>/dev/null || echo "0")
INITIAL_ROW_COUNT=$(cat /tmp/initial_repository_row_count 2>/dev/null || echo "0")

CURRENT_REPO_COUNT=$(get_repository_count)
CURRENT_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')

# Search for the expected inventory (repository)
EXPECTED_INVENTORY="Lab Reagents"
REPO_DATA=$(scinote_db_query "SELECT id, name, created_at FROM repositories WHERE LOWER(TRIM(name)) = LOWER(TRIM('${EXPECTED_INVENTORY}')) ORDER BY created_at DESC LIMIT 1;")

REPO_FOUND="false"
REPO_ID=""
REPO_NAME=""
REPO_CREATED=""

if [ -n "$REPO_DATA" ]; then
    REPO_FOUND="true"
    REPO_ID=$(echo "$REPO_DATA" | cut -d'|' -f1)
    REPO_NAME=$(echo "$REPO_DATA" | cut -d'|' -f2)
    REPO_CREATED=$(echo "$REPO_DATA" | cut -d'|' -f3)
fi

# Search for the expected item (repository_row)
EXPECTED_ITEM="Tris-HCl Buffer pH 7.4"
ITEM_DATA=$(scinote_db_query "SELECT rr.id, rr.name, r.name, rr.created_at FROM repository_rows rr JOIN repositories r ON rr.repository_id = r.id WHERE LOWER(TRIM(rr.name)) = LOWER(TRIM('${EXPECTED_ITEM}')) ORDER BY rr.created_at DESC LIMIT 1;")

ITEM_FOUND="false"
ITEM_ID=""
ITEM_NAME=""
ITEM_REPO_NAME=""
ITEM_CREATED=""

if [ -n "$ITEM_DATA" ]; then
    ITEM_FOUND="true"
    ITEM_ID=$(echo "$ITEM_DATA" | cut -d'|' -f1)
    ITEM_NAME=$(echo "$ITEM_DATA" | cut -d'|' -f2)
    ITEM_REPO_NAME=$(echo "$ITEM_DATA" | cut -d'|' -f3)
    ITEM_CREATED=$(echo "$ITEM_DATA" | cut -d'|' -f4)
fi

# Partial match fallbacks
PARTIAL_REPO=""
if [ "$REPO_FOUND" = "false" ]; then
    PARTIAL_REPO=$(scinote_db_query "SELECT id, name FROM repositories WHERE LOWER(name) LIKE '%reagent%' OR LOWER(name) LIKE '%lab%' ORDER BY created_at DESC LIMIT 1;")
fi

PARTIAL_ITEM=""
if [ "$ITEM_FOUND" = "false" ]; then
    PARTIAL_ITEM=$(scinote_db_query "SELECT rr.id, rr.name FROM repository_rows rr WHERE LOWER(rr.name) LIKE '%tris%' OR LOWER(rr.name) LIKE '%buffer%' ORDER BY rr.created_at DESC LIMIT 1;")
fi

REPO_NAME_ESCAPED=$(json_escape "$REPO_NAME")
ITEM_NAME_ESCAPED=$(json_escape "$ITEM_NAME")
ITEM_REPO_NAME_ESCAPED=$(json_escape "$ITEM_REPO_NAME")
PARTIAL_REPO_ESCAPED=$(json_escape "$PARTIAL_REPO")
PARTIAL_ITEM_ESCAPED=$(json_escape "$PARTIAL_ITEM")

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
    "item_found": ${ITEM_FOUND},
    "item": {
        "id": "${ITEM_ID}",
        "name": "${ITEM_NAME_ESCAPED}",
        "repository_name": "${ITEM_REPO_NAME_ESCAPED}",
        "created_at": "${ITEM_CREATED}"
    },
    "partial_repo_match": "${PARTIAL_REPO_ESCAPED}",
    "partial_item_match": "${PARTIAL_ITEM_ESCAPED}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_json "/tmp/create_inventory_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/create_inventory_result.json"
cat /tmp/create_inventory_result.json
echo "=== Export complete ==="
