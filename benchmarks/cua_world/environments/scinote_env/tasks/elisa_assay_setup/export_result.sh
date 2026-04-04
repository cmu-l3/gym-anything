#!/bin/bash
echo "=== Exporting elisa_assay_setup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/elisa_assay_setup_end_screenshot.png

# ---- Find project and experiment ----
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='ELISA Assay Development - IL-6' LIMIT 1;" | tr -d '[:space:]')
EXPERIMENT_ID=""
EXP_FOUND="false"

if [ -n "$PROJECT_ID" ]; then
    EXP_DATA=$(scinote_db_query "SELECT id FROM experiments WHERE project_id=${PROJECT_ID} AND LOWER(name) LIKE '%antibody%pair%optim%' LIMIT 1;")
    if [ -n "$EXP_DATA" ]; then
        EXP_FOUND="true"
        EXPERIMENT_ID=$(echo "$EXP_DATA" | tr -d '[:space:]')
    fi
fi

# ---- Find the 4 tasks ----
TASK_COAT_ID=""
TASK_DILUT_ID=""
TASK_PRIMARY_ID=""
TASK_SIGNAL_ID=""
TASK_COUNT=0
ALL_TASKS_JSON="[]"

if [ "$EXP_FOUND" = "true" ] && [ -n "$EXPERIMENT_ID" ]; then
    TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;" | tr -d '[:space:]')

    TCOAT=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%plate%coat%' AND archived=false LIMIT 1;")
    [ -n "$TCOAT" ] && TASK_COAT_ID=$(echo "$TCOAT" | tr -d '[:space:]')

    TDILUT=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%sample%dilut%' AND archived=false LIMIT 1;")
    [ -n "$TDILUT" ] && TASK_DILUT_ID=$(echo "$TDILUT" | tr -d '[:space:]')

    TPRIMARY=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%primary%antibody%' AND archived=false LIMIT 1;")
    [ -n "$TPRIMARY" ] && TASK_PRIMARY_ID=$(echo "$TPRIMARY" | tr -d '[:space:]')

    TSIGNAL=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%signal%detect%' AND archived=false LIMIT 1;")
    [ -n "$TSIGNAL" ] && TASK_SIGNAL_ID=$(echo "$TSIGNAL" | tr -d '[:space:]')

    TNAMES_RAW=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;")
    ALL_TASKS_JSON="["
    TN_FIRST=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$TN_FIRST" = true ]; then TN_FIRST=false; else ALL_TASKS_JSON="${ALL_TASKS_JSON}, "; fi
        ALL_TASKS_JSON="${ALL_TASKS_JSON}\"${tname_c}\""
    done <<< "$TNAMES_RAW"
    ALL_TASKS_JSON="${ALL_TASKS_JSON}]"
fi

# ---- Check connections ----
CONN_COAT_DILUT="false"
CONN_DILUT_PRIMARY="false"
CONN_PRIMARY_SIGNAL="false"

if [ -n "$TASK_COAT_ID" ] && [ -n "$TASK_DILUT_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK_COAT_ID} AND input_id=${TASK_DILUT_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_COAT_DILUT="true"
fi
if [ -n "$TASK_DILUT_ID" ] && [ -n "$TASK_PRIMARY_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK_DILUT_ID} AND input_id=${TASK_PRIMARY_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_DILUT_PRIMARY="true"
fi
if [ -n "$TASK_PRIMARY_ID" ] && [ -n "$TASK_SIGNAL_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${TASK_PRIMARY_ID} AND input_id=${TASK_SIGNAL_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_PRIMARY_SIGNAL="true"
fi

# ---- Protocol steps for Plate Coating ----
COAT_STEP_COUNT=0
if [ -n "$TASK_COAT_ID" ]; then
    PROTO_ID=$(scinote_db_query "SELECT id FROM protocols WHERE my_module_id=${TASK_COAT_ID} LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PROTO_ID" ]; then
        COAT_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')
    fi
fi

# ---- Inventory 'ELISA Consumables' ----
REPO_ID=$(cat /tmp/elisa_repo_id 2>/dev/null || echo "")
if [ -z "$REPO_ID" ]; then
    REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='ELISA Consumables' AND team_id=1 LIMIT 1;" | tr -d '[:space:]')
fi

COL_COUNT=0
ITEM_COUNT=0
COLUMNS_JSON="[]"
ITEMS_JSON="[]"
CATALOG_COL_ID=""
HAS_VOLUME_COL="false"
HAS_STORAGE_COL="false"

if [ -n "$REPO_ID" ]; then
    COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    COL_DATA=$(scinote_db_query "SELECT id, name FROM repository_columns WHERE repository_id=${REPO_ID} ORDER BY id;")

    COLUMNS_JSON="["
    COL_FIRST=true
    while IFS='|' read -r col_id col_name; do
        [ -z "$col_id" ] && continue
        col_id_c=$(echo "$col_id" | tr -d '[:space:]')
        col_name_c=$(echo "$col_name" | sed 's/"/\\"/g' | xargs)
        if [ "$COL_FIRST" = true ]; then COL_FIRST=false; else COLUMNS_JSON="${COLUMNS_JSON}, "; fi
        COLUMNS_JSON="${COLUMNS_JSON}\"${col_name_c}\""
        echo "$col_name" | grep -qi "catalog" && CATALOG_COL_ID="$col_id_c"
        echo "$col_name" | grep -qi "volume" && HAS_VOLUME_COL="true"
        echo "$col_name" | grep -qi "storage" && HAS_STORAGE_COL="true"
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

RESULT_JSON=$(cat << JSONEOF
{
    "project_id": "${PROJECT_ID}",
    "experiment_found": ${EXP_FOUND},
    "experiment_id": "${EXPERIMENT_ID}",
    "task_count": ${TASK_COUNT:-0},
    "all_tasks": ${ALL_TASKS_JSON},
    "task_coat_id": "${TASK_COAT_ID}",
    "task_dilut_id": "${TASK_DILUT_ID}",
    "task_primary_id": "${TASK_PRIMARY_ID}",
    "task_signal_id": "${TASK_SIGNAL_ID}",
    "conn_coat_to_dilut": ${CONN_COAT_DILUT},
    "conn_dilut_to_primary": ${CONN_DILUT_PRIMARY},
    "conn_primary_to_signal": ${CONN_PRIMARY_SIGNAL},
    "plate_coating_step_count": ${COAT_STEP_COUNT:-0},
    "inventory_column_count": ${COL_COUNT:-0},
    "inventory_columns": ${COLUMNS_JSON},
    "has_volume_column": ${HAS_VOLUME_COL},
    "has_storage_column": ${HAS_STORAGE_COL},
    "inventory_item_count": ${ITEM_COUNT:-0},
    "inventory_items": ${ITEMS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF
)

safe_write_json "/tmp/elisa_assay_setup_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/elisa_assay_setup_result.json"
cat /tmp/elisa_assay_setup_result.json
echo "=== Export complete ==="
