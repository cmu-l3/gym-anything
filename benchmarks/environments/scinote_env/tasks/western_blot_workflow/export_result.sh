#!/bin/bash
echo "=== Exporting western_blot_workflow result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/western_blot_workflow_end_screenshot.png

INITIAL_COUNTS=$(cat /tmp/wb_initial_counts.json 2>/dev/null || echo "{}")

# ---- Find project and experiment ----
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Western Blot - p53 Expression Study' LIMIT 1;" | tr -d '[:space:]')
EXPERIMENT_ID=""
if [ -n "$PROJECT_ID" ]; then
    EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='SDS-PAGE Workflow' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
fi

if [ -z "$EXPERIMENT_ID" ]; then
    # Fallback from cache
    EXPERIMENT_ID=$(cat /tmp/wb_experiment_id 2>/dev/null || echo "")
fi

# ---- Find the 4 tasks ----
TASK_SAMPLE_ID=""
TASK_SDSPAGE_ID=""
TASK_TRANSFER_ID=""
TASK_DETECT_ID=""
ALL_TASK_NAMES_JSON="[]"
TASK_COUNT=0

if [ -n "$EXPERIMENT_ID" ]; then
    TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;" | tr -d '[:space:]')

    TSAMPLE=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%sample%prep%' AND archived=false LIMIT 1;")
    [ -n "$TSAMPLE" ] && TASK_SAMPLE_ID=$(echo "$TSAMPLE" | tr -d '[:space:]')

    TSDSPAGE=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%sds%page%' AND archived=false LIMIT 1;")
    [ -n "$TSDSPAGE" ] && TASK_SDSPAGE_ID=$(echo "$TSDSPAGE" | tr -d '[:space:]')

    TTRANSFER=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%membrane%transfer%' AND archived=false LIMIT 1;")
    [ -n "$TTRANSFER" ] && TASK_TRANSFER_ID=$(echo "$TTRANSFER" | tr -d '[:space:]')

    TDETECT=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%detect%imag%' AND archived=false LIMIT 1;")
    [ -n "$TDETECT" ] && TASK_DETECT_ID=$(echo "$TDETECT" | tr -d '[:space:]')

    TNAMES_RAW=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;")
    ALL_TASK_NAMES_JSON="["
    TN_FIRST=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$TN_FIRST" = true ]; then TN_FIRST=false; else ALL_TASK_NAMES_JSON="${ALL_TASK_NAMES_JSON}, "; fi
        ALL_TASK_NAMES_JSON="${ALL_TASK_NAMES_JSON}\"${tname_c}\""
    done <<< "$TNAMES_RAW"
    ALL_TASK_NAMES_JSON="${ALL_TASK_NAMES_JSON}]"
fi

# ---- Check connections ----
CONN_SAMPLE_SDSPAGE="false"
CONN_SDSPAGE_TRANSFER="false"
CONN_TRANSFER_DETECT="false"

if [ -n "$TASK_SAMPLE_ID" ] && [ -n "$TASK_SDSPAGE_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK_SAMPLE_ID} AND input_id=${TASK_SDSPAGE_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_SAMPLE_SDSPAGE="true"
fi
if [ -n "$TASK_SDSPAGE_ID" ] && [ -n "$TASK_TRANSFER_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK_SDSPAGE_ID} AND input_id=${TASK_TRANSFER_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_SDSPAGE_TRANSFER="true"
fi
if [ -n "$TASK_TRANSFER_ID" ] && [ -n "$TASK_DETECT_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK_TRANSFER_ID} AND input_id=${TASK_DETECT_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_TRANSFER_DETECT="true"
fi

# ---- Protocol steps for Membrane Transfer ----
TRANSFER_STEP_COUNT=0
if [ -n "$TASK_TRANSFER_ID" ]; then
    PROTO_ID=$(scinote_db_query "SELECT id FROM protocols WHERE my_module_id=${TASK_TRANSFER_ID} LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PROTO_ID" ]; then
        TRANSFER_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')
    fi
fi

# ---- Find inventory 'Western Blot Reagents' ----
REPO_DATA=$(scinote_db_query "SELECT id, name FROM repositories WHERE LOWER(TRIM(name)) LIKE LOWER('%western%blot%reagent%') LIMIT 1;")
REPO_FOUND="false"
REPO_ID=""
REPO_NAME=""
COL_COUNT=0
ITEM_COUNT=0
COLUMNS_JSON="[]"
ITEMS_JSON="[]"

# For catalog number lookup
CATALOG_COL_ID=""
SUPPLIER_COL_ID=""

if [ -n "$REPO_DATA" ]; then
    REPO_FOUND="true"
    REPO_ID=$(echo "$REPO_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
    REPO_NAME=$(echo "$REPO_DATA" | cut -d'|' -f2 | xargs)

    COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    COL_DATA=$(scinote_db_query "SELECT id, name FROM repository_columns WHERE repository_id=${REPO_ID} ORDER BY id;")
    COLUMNS_JSON="["
    COL_FIRST=true
    while IFS='|' read -r col_id col_name; do
        [ -z "$col_id" ] && continue
        col_name_c=$(echo "$col_name" | sed 's/"/\\"/g' | xargs)
        col_id_c=$(echo "$col_id" | tr -d '[:space:]')
        if [ "$COL_FIRST" = true ]; then COL_FIRST=false; else COLUMNS_JSON="${COLUMNS_JSON}, "; fi
        COLUMNS_JSON="${COLUMNS_JSON}\"${col_name_c}\""
        echo "$col_name" | grep -qi "catalog" && CATALOG_COL_ID="$col_id_c"
        echo "$col_name" | grep -qi "supplier" && SUPPLIER_COL_ID="$col_id_c"
    done <<< "$COL_DATA"
    COLUMNS_JSON="${COLUMNS_JSON}]"

    ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    ITEM_DATA=$(scinote_db_query "SELECT id, name FROM repository_rows WHERE repository_id=${REPO_ID} ORDER BY id;")
    ITEMS_JSON="["
    ITEM_FIRST=true
    while IFS='|' read -r row_id row_name; do
        [ -z "$row_id" ] && continue
        row_id_c=$(echo "$row_id" | tr -d '[:space:]')
        row_name_c=$(echo "$row_name" | sed 's/"/\\"/g' | xargs)

        # Get catalog number
        CATALOG_VAL=""
        if [ -n "$CATALOG_COL_ID" ]; then
            CATALOG_VAL=$(scinote_db_query "SELECT rtv.data FROM repository_cells rc JOIN repository_text_values rtv ON rc.value_type='RepositoryTextValue' AND rc.value_id=rtv.id WHERE rc.repository_row_id=${row_id_c} AND rc.repository_column_id=${CATALOG_COL_ID} LIMIT 1;" 2>/dev/null | xargs)
        fi
        CATALOG_VAL_C=$(echo "$CATALOG_VAL" | sed 's/"/\\"/g')

        if [ "$ITEM_FIRST" = true ]; then ITEM_FIRST=false; else ITEMS_JSON="${ITEMS_JSON}, "; fi
        ITEMS_JSON="${ITEMS_JSON}{\"name\": \"${row_name_c}\", \"catalog_number\": \"${CATALOG_VAL_C}\"}"
    done <<< "$ITEM_DATA"
    ITEMS_JSON="${ITEMS_JSON}]"
fi

REPO_NAME_ESC=$(json_escape "$REPO_NAME")

RESULT_JSON=$(cat << JSONEOF
{
    "experiment_id": "${EXPERIMENT_ID}",
    "task_count": ${TASK_COUNT:-0},
    "all_task_names": ${ALL_TASK_NAMES_JSON},
    "task_sample_id": "${TASK_SAMPLE_ID}",
    "task_sdspage_id": "${TASK_SDSPAGE_ID}",
    "task_transfer_id": "${TASK_TRANSFER_ID}",
    "task_detect_id": "${TASK_DETECT_ID}",
    "conn_sample_to_sdspage": ${CONN_SAMPLE_SDSPAGE},
    "conn_sdspage_to_transfer": ${CONN_SDSPAGE_TRANSFER},
    "conn_transfer_to_detect": ${CONN_TRANSFER_DETECT},
    "membrane_transfer_step_count": ${TRANSFER_STEP_COUNT:-0},
    "inventory_found": ${REPO_FOUND},
    "inventory_name": "${REPO_NAME_ESC}",
    "inventory_column_count": ${COL_COUNT:-0},
    "inventory_columns": ${COLUMNS_JSON},
    "inventory_item_count": ${ITEM_COUNT:-0},
    "inventory_items": ${ITEMS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF
)

safe_write_json "/tmp/western_blot_workflow_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/western_blot_workflow_result.json"
cat /tmp/western_blot_workflow_result.json
echo "=== Export complete ==="
