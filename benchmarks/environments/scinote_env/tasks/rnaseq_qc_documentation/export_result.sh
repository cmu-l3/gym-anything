#!/bin/bash
echo "=== Exporting rnaseq_qc_documentation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/rnaseq_qc_documentation_end_screenshot.png

# ---- Find project ----
PROJECT_DATA=$(scinote_db_query "SELECT id, name FROM projects WHERE LOWER(TRIM(name)) = LOWER(TRIM('RNA-seq Quality Control Pipeline')) LIMIT 1;")
PROJECT_FOUND="false"
PROJECT_ID=""

if [ -n "$PROJECT_DATA" ]; then
    PROJECT_FOUND="true"
    PROJECT_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
fi

# ---- Find experiments ----
EXP1_ID=""
EXP1_FOUND="false"
EXP2_ID=""
EXP2_FOUND="false"
EXPERIMENTS_JSON="[]"

if [ -n "$PROJECT_ID" ]; then
    E1=$(scinote_db_query "SELECT id FROM experiments WHERE project_id=${PROJECT_ID} AND LOWER(name) LIKE '%library%qc%' LIMIT 1;")
    if [ -n "$E1" ]; then EXP1_FOUND="true"; EXP1_ID=$(echo "$E1" | tr -d '[:space:]'); fi

    E2=$(scinote_db_query "SELECT id FROM experiments WHERE project_id=${PROJECT_ID} AND LOWER(name) LIKE '%bioinformat%' LIMIT 1;")
    if [ -n "$E2" ]; then EXP2_FOUND="true"; EXP2_ID=$(echo "$E2" | tr -d '[:space:]'); fi

    ENAMES=$(scinote_db_query "SELECT name FROM experiments WHERE project_id=${PROJECT_ID};")
    EXPERIMENTS_JSON="["
    EF=true
    while IFS= read -r ename; do
        [ -z "$ename" ] && continue
        ename_c=$(echo "$ename" | sed 's/"/\\"/g' | xargs)
        if [ "$EF" = true ]; then EF=false; else EXPERIMENTS_JSON="${EXPERIMENTS_JSON}, "; fi
        EXPERIMENTS_JSON="${EXPERIMENTS_JSON}\"${ename_c}\""
    done <<< "$ENAMES"
    EXPERIMENTS_JSON="${EXPERIMENTS_JSON}]"
fi

# ---- Tasks in Experiment 1 (Library QC Assessment) ----
T_EXTRACT_ID=""
T_QUALITY_ID=""
T_LIBPREP_ID=""
T_QUANT_ID=""
EXP1_TASK_COUNT=0
EXP1_TASKS_JSON="[]"

if [ "$EXP1_FOUND" = "true" ]; then
    EXP1_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXP1_ID} AND archived=false;" | tr -d '[:space:]')

    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP1_ID} AND LOWER(name) LIKE '%rna%extract%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && T_EXTRACT_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP1_ID} AND LOWER(name) LIKE '%rna%quality%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && T_QUALITY_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP1_ID} AND LOWER(name) LIKE '%library%prep%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && T_LIBPREP_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP1_ID} AND LOWER(name) LIKE '%library%quant%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && T_QUANT_ID=$(echo "$D" | tr -d '[:space:]')

    TNAMES=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXP1_ID} AND archived=false;")
    EXP1_TASKS_JSON="["
    TF=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$TF" = true ]; then TF=false; else EXP1_TASKS_JSON="${EXP1_TASKS_JSON}, "; fi
        EXP1_TASKS_JSON="${EXP1_TASKS_JSON}\"${tname_c}\""
    done <<< "$TNAMES"
    EXP1_TASKS_JSON="${EXP1_TASKS_JSON}]"
fi

# ---- Tasks in Experiment 2 (Bioinformatics Pipeline) ----
T_TRIM_ID=""
T_ALIGN_ID=""
T_QUANT2_ID=""
EXP2_TASK_COUNT=0
EXP2_TASKS_JSON="[]"

if [ "$EXP2_FOUND" = "true" ]; then
    EXP2_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXP2_ID} AND archived=false;" | tr -d '[:space:]')

    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP2_ID} AND LOWER(name) LIKE '%read%trim%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && T_TRIM_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP2_ID} AND LOWER(name) LIKE '%reference%align%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && T_ALIGN_ID=$(echo "$D" | tr -d '[:space:]')
    D=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP2_ID} AND LOWER(name) LIKE '%expression%quant%' AND archived=false LIMIT 1;")
    [ -n "$D" ] && T_QUANT2_ID=$(echo "$D" | tr -d '[:space:]')

    TNAMES=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXP2_ID} AND archived=false;")
    EXP2_TASKS_JSON="["
    TF=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$TF" = true ]; then TF=false; else EXP2_TASKS_JSON="${EXP2_TASKS_JSON}, "; fi
        EXP2_TASKS_JSON="${EXP2_TASKS_JSON}\"${tname_c}\""
    done <<< "$TNAMES"
    EXP2_TASKS_JSON="${EXP2_TASKS_JSON}]"
fi

# ---- Connections ----
CONN_EXTRACT_QUALITY="false"
CONN_QUALITY_LIBPREP="false"
CONN_LIBPREP_QUANT="false"
CONN_TRIM_ALIGN="false"
CONN_ALIGN_QUANT="false"

check_conn() {
    local out_id="$1" in_id="$2"
    [ -z "$out_id" ] || [ -z "$in_id" ] && echo "false" && return
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${out_id} AND input_id=${in_id};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && echo "true" || echo "false"
}

[ -n "$T_EXTRACT_ID" ] && [ -n "$T_QUALITY_ID" ] && CONN_EXTRACT_QUALITY=$(check_conn "$T_EXTRACT_ID" "$T_QUALITY_ID")
[ -n "$T_QUALITY_ID" ] && [ -n "$T_LIBPREP_ID" ] && CONN_QUALITY_LIBPREP=$(check_conn "$T_QUALITY_ID" "$T_LIBPREP_ID")
[ -n "$T_LIBPREP_ID" ] && [ -n "$T_QUANT_ID" ] && CONN_LIBPREP_QUANT=$(check_conn "$T_LIBPREP_ID" "$T_QUANT_ID")
[ -n "$T_TRIM_ID" ] && [ -n "$T_ALIGN_ID" ] && CONN_TRIM_ALIGN=$(check_conn "$T_TRIM_ID" "$T_ALIGN_ID")
[ -n "$T_ALIGN_ID" ] && [ -n "$T_QUANT2_ID" ] && CONN_ALIGN_QUANT=$(check_conn "$T_ALIGN_ID" "$T_QUANT2_ID")

# ---- Protocol steps for Library Preparation ----
LIBPREP_STEP_COUNT=0
if [ -n "$T_LIBPREP_ID" ]; then
    PROTO_ID=$(scinote_db_query "SELECT id FROM protocols WHERE my_module_id=${T_LIBPREP_ID} LIMIT 1;" | tr -d '[:space:]')
    [ -n "$PROTO_ID" ] && LIBPREP_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')
fi

# ---- Inventory 'RNA-seq Reagents' ----
REPO_DATA=$(scinote_db_query "SELECT id, name FROM repositories WHERE LOWER(TRIM(name)) LIKE LOWER('%rna%seq%reagent%') LIMIT 1;")
REPO_FOUND="false"
REPO_ID=""
COL_COUNT=0
ITEM_COUNT=0
COLUMNS_JSON="[]"
ITEMS_JSON="[]"

if [ -n "$REPO_DATA" ]; then
    REPO_FOUND="true"
    REPO_ID=$(echo "$REPO_DATA" | cut -d'|' -f1 | tr -d '[:space:]')

    COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    COL_NAMES=$(scinote_db_query "SELECT name FROM repository_columns WHERE repository_id=${REPO_ID} ORDER BY id;")
    COLUMNS_JSON="["
    CF=true
    while IFS= read -r cname; do
        [ -z "$cname" ] && continue
        cname_c=$(echo "$cname" | sed 's/"/\\"/g' | xargs)
        if [ "$CF" = true ]; then CF=false; else COLUMNS_JSON="${COLUMNS_JSON}, "; fi
        COLUMNS_JSON="${COLUMNS_JSON}\"${cname_c}\""
    done <<< "$COL_NAMES"
    COLUMNS_JSON="${COLUMNS_JSON}]"

    ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    ITEM_NAMES=$(scinote_db_query "SELECT name FROM repository_rows WHERE repository_id=${REPO_ID} ORDER BY id;")
    ITEMS_JSON="["
    IF=true
    while IFS= read -r iname; do
        [ -z "$iname" ] && continue
        iname_c=$(echo "$iname" | sed 's/"/\\"/g' | xargs)
        if [ "$IF" = true ]; then IF=false; else ITEMS_JSON="${ITEMS_JSON}, "; fi
        ITEMS_JSON="${ITEMS_JSON}\"${iname_c}\""
    done <<< "$ITEM_NAMES"
    ITEMS_JSON="${ITEMS_JSON}]"
fi

RESULT_JSON=$(cat << JSONEOF
{
    "project_found": ${PROJECT_FOUND},
    "project_id": "${PROJECT_ID}",
    "exp1_found": ${EXP1_FOUND},
    "exp1_id": "${EXP1_ID}",
    "exp2_found": ${EXP2_FOUND},
    "exp2_id": "${EXP2_ID}",
    "experiments": ${EXPERIMENTS_JSON},
    "exp1_task_count": ${EXP1_TASK_COUNT:-0},
    "exp1_tasks": ${EXP1_TASKS_JSON},
    "exp2_task_count": ${EXP2_TASK_COUNT:-0},
    "exp2_tasks": ${EXP2_TASKS_JSON},
    "conn_extract_quality": ${CONN_EXTRACT_QUALITY},
    "conn_quality_libprep": ${CONN_QUALITY_LIBPREP},
    "conn_libprep_quant": ${CONN_LIBPREP_QUANT},
    "conn_trim_align": ${CONN_TRIM_ALIGN},
    "conn_align_quant": ${CONN_ALIGN_QUANT},
    "libprep_protocol_step_count": ${LIBPREP_STEP_COUNT:-0},
    "inventory_found": ${REPO_FOUND},
    "inventory_column_count": ${COL_COUNT:-0},
    "inventory_columns": ${COLUMNS_JSON},
    "inventory_item_count": ${ITEM_COUNT:-0},
    "inventory_items": ${ITEMS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF
)

safe_write_json "/tmp/rnaseq_qc_documentation_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/rnaseq_qc_documentation_result.json"
cat /tmp/rnaseq_qc_documentation_result.json
echo "=== Export complete ==="
