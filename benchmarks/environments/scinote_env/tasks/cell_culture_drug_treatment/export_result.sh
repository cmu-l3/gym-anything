#!/bin/bash
echo "=== Exporting cell_culture_drug_treatment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cell_culture_drug_treatment_end_screenshot.png

# ---- Find project and experiment ----
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='HeLa Cell Doxorubicin Dose Response' LIMIT 1;" | tr -d '[:space:]')
EXPERIMENT_ID=$(cat /tmp/cdt_experiment_id 2>/dev/null || echo "")
if [ -z "$EXPERIMENT_ID" ] && [ -n "$PROJECT_ID" ]; then
    EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Dose Response Analysis' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
fi

# ---- Find the 4 tasks ----
TASK_SEED_ID=""
TASK_DRUG_ID=""
TASK_VIAB_ID=""
TASK_ANAL_ID=""
TASK_COUNT=0
ALL_TASKS_JSON="[]"

if [ -n "$EXPERIMENT_ID" ]; then
    TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;" | tr -d '[:space:]')

    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%cell%seed%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && TASK_SEED_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%drug%treat%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && TASK_DRUG_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%cell%viab%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && TASK_VIAB_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND LOWER(name) LIKE '%data%anal%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && TASK_ANAL_ID=$(echo "$D" | tr -d '[:space:]')

    TNAMES=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;")
    ALL_TASKS_JSON="["
    TF=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$TF" = true ]; then TF=false; else ALL_TASKS_JSON="${ALL_TASKS_JSON}, "; fi
        ALL_TASKS_JSON="${ALL_TASKS_JSON}\"${tname_c}\""
    done <<< "$TNAMES"
    ALL_TASKS_JSON="${ALL_TASKS_JSON}]"
fi

# ---- Check connections ----
CONN_SEED_DRUG="false"
CONN_DRUG_VIAB="false"
CONN_VIAB_ANAL="false"

check_conn() {
    local out_id="$1" in_id="$2"
    [ -z "$out_id" ] || [ -z "$in_id" ] && echo "false" && return
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${out_id} AND input_id=${in_id};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && echo "true" || echo "false"
}

[ -n "$TASK_SEED_ID" ] && [ -n "$TASK_DRUG_ID" ] && CONN_SEED_DRUG=$(check_conn "$TASK_SEED_ID" "$TASK_DRUG_ID")
[ -n "$TASK_DRUG_ID" ] && [ -n "$TASK_VIAB_ID" ] && CONN_DRUG_VIAB=$(check_conn "$TASK_DRUG_ID" "$TASK_VIAB_ID")
[ -n "$TASK_VIAB_ID" ] && [ -n "$TASK_ANAL_ID" ] && CONN_VIAB_ANAL=$(check_conn "$TASK_VIAB_ID" "$TASK_ANAL_ID")

# ---- Protocol steps for Drug Treatment ----
DRUG_STEP_COUNT=0
if [ -n "$TASK_DRUG_ID" ]; then
    PROTO_ID=$(scinote_db_query "SELECT id FROM protocols WHERE my_module_id=${TASK_DRUG_ID} LIMIT 1;" | tr -d '[:space:]')
    [ -n "$PROTO_ID" ] && DRUG_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')
fi

# ---- Inventory 'Drug Stocks' ----
REPO_ID=$(cat /tmp/cdt_repo_id 2>/dev/null || echo "")
if [ -z "$REPO_ID" ]; then
    REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='Drug Stocks' AND team_id=1 LIMIT 1;" | tr -d '[:space:]')
fi

COL_COUNT=0
ITEM_COUNT=0
COLUMNS_JSON="[]"
ITEMS_JSON="[]"
CONC_COL_ID=""
SOLVENT_COL_ID=""
STORAGE_COL_ID=""
HAS_SOLVENT_COL="false"
HAS_STORAGE_COL="false"

if [ -n "$REPO_ID" ]; then
    COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    COL_DATA=$(scinote_db_query "SELECT id, name FROM repository_columns WHERE repository_id=${REPO_ID} ORDER BY id;")
    COLUMNS_JSON="["
    CF=true
    while IFS='|' read -r col_id col_name; do
        [ -z "$col_id" ] && continue
        col_id_c=$(echo "$col_id" | tr -d '[:space:]')
        col_name_c=$(echo "$col_name" | sed 's/"/\\"/g' | xargs)
        if [ "$CF" = true ]; then CF=false; else COLUMNS_JSON="${COLUMNS_JSON}, "; fi
        COLUMNS_JSON="${COLUMNS_JSON}\"${col_name_c}\""
        # Identify columns
        echo "$col_name" | grep -qi "concentrat" && CONC_COL_ID="$col_id_c"
        echo "$col_name" | grep -qi "solvent" && SOLVENT_COL_ID="$col_id_c" && HAS_SOLVENT_COL="true"
        echo "$col_name" | grep -qi "storage" && STORAGE_COL_ID="$col_id_c" && HAS_STORAGE_COL="true"
    done <<< "$COL_DATA"
    COLUMNS_JSON="${COLUMNS_JSON}]"

    ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    ITEM_DATA=$(scinote_db_query "SELECT id, name FROM repository_rows WHERE repository_id=${REPO_ID} ORDER BY id;")
    ITEMS_JSON="["
    IF=true
    while IFS='|' read -r row_id row_name; do
        [ -z "$row_id" ] && continue
        row_id_c=$(echo "$row_id" | tr -d '[:space:]')
        row_name_c=$(echo "$row_name" | sed 's/"/\\"/g' | xargs)

        # Get concentration value
        CONC_VAL=""
        if [ -n "$CONC_COL_ID" ]; then
            CONC_VAL=$(scinote_db_query "SELECT rtv.data FROM repository_cells rc JOIN repository_text_values rtv ON rc.value_type='RepositoryTextValue' AND rc.value_id=rtv.id WHERE rc.repository_row_id=${row_id_c} AND rc.repository_column_id=${CONC_COL_ID} LIMIT 1;" 2>/dev/null | xargs)
        fi
        CONC_VAL_C=$(echo "$CONC_VAL" | sed 's/"/\\"/g')

        # Get solvent value
        SOLVENT_VAL=""
        if [ -n "$SOLVENT_COL_ID" ]; then
            SOLVENT_VAL=$(scinote_db_query "SELECT rtv.data FROM repository_cells rc JOIN repository_text_values rtv ON rc.value_type='RepositoryTextValue' AND rc.value_id=rtv.id WHERE rc.repository_row_id=${row_id_c} AND rc.repository_column_id=${SOLVENT_COL_ID} LIMIT 1;" 2>/dev/null | xargs)
        fi
        SOLVENT_VAL_C=$(echo "$SOLVENT_VAL" | sed 's/"/\\"/g')

        if [ "$IF" = true ]; then IF=false; else ITEMS_JSON="${ITEMS_JSON}, "; fi
        ITEMS_JSON="${ITEMS_JSON}{\"name\": \"${row_name_c}\", \"concentration\": \"${CONC_VAL_C}\", \"solvent\": \"${SOLVENT_VAL_C}\"}"
    done <<< "$ITEM_DATA"
    ITEMS_JSON="${ITEMS_JSON}]"
fi

RESULT_JSON=$(cat << JSONEOF
{
    "experiment_id": "${EXPERIMENT_ID}",
    "task_count": ${TASK_COUNT:-0},
    "all_tasks": ${ALL_TASKS_JSON},
    "task_seed_id": "${TASK_SEED_ID}",
    "task_drug_id": "${TASK_DRUG_ID}",
    "task_viab_id": "${TASK_VIAB_ID}",
    "task_anal_id": "${TASK_ANAL_ID}",
    "conn_seed_to_drug": ${CONN_SEED_DRUG},
    "conn_drug_to_viab": ${CONN_DRUG_VIAB},
    "conn_viab_to_anal": ${CONN_VIAB_ANAL},
    "drug_treatment_step_count": ${DRUG_STEP_COUNT:-0},
    "inventory_column_count": ${COL_COUNT:-0},
    "inventory_columns": ${COLUMNS_JSON},
    "has_solvent_column": ${HAS_SOLVENT_COL},
    "has_storage_column": ${HAS_STORAGE_COL},
    "inventory_item_count": ${ITEM_COUNT:-0},
    "inventory_items": ${ITEMS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF
)

safe_write_json "/tmp/cell_culture_drug_treatment_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/cell_culture_drug_treatment_result.json"
cat /tmp/cell_culture_drug_treatment_result.json
echo "=== Export complete ==="
