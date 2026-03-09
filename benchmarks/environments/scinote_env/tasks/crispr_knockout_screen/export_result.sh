#!/bin/bash
echo "=== Exporting crispr_knockout_screen result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/crispr_knockout_screen_end_screenshot.png

# ---- Find the target project ----
PROJECT_DATA=$(scinote_db_query "SELECT id, name FROM projects WHERE LOWER(TRIM(name)) = LOWER(TRIM('CRISPR Knockout Screen - KRAS')) LIMIT 1;")
PROJECT_FOUND="false"
PROJECT_ID=""
PROJECT_NAME=""

if [ -n "$PROJECT_DATA" ]; then
    PROJECT_FOUND="true"
    PROJECT_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
    PROJECT_NAME=$(echo "$PROJECT_DATA" | cut -d'|' -f2 | xargs)
fi

# ---- Find experiments in project ----
EXP1_ID=""
EXP1_FOUND="false"
EXP2_ID=""
EXP2_FOUND="false"
EXPERIMENTS_JSON="[]"

if [ -n "$PROJECT_ID" ]; then
    # Experiment 1: sgRNA Library Synthesis
    EXP1_DATA=$(scinote_db_query "SELECT id FROM experiments WHERE project_id=${PROJECT_ID} AND LOWER(name) LIKE '%sgrna%library%synth%' LIMIT 1;")
    if [ -n "$EXP1_DATA" ]; then
        EXP1_FOUND="true"
        EXP1_ID=$(echo "$EXP1_DATA" | tr -d '[:space:]')
    fi

    # Experiment 2: Cell Line Engineering
    EXP2_DATA=$(scinote_db_query "SELECT id FROM experiments WHERE project_id=${PROJECT_ID} AND LOWER(name) LIKE '%cell%line%engineer%' LIMIT 1;")
    if [ -n "$EXP2_DATA" ]; then
        EXP2_FOUND="true"
        EXP2_ID=$(echo "$EXP2_DATA" | tr -d '[:space:]')
    fi

    # All experiment names
    EXP_NAMES_RAW=$(scinote_db_query "SELECT name FROM experiments WHERE project_id=${PROJECT_ID};")
    EXPERIMENTS_JSON="["
    EXP_FIRST=true
    while IFS= read -r ename; do
        [ -z "$ename" ] && continue
        ename_clean=$(echo "$ename" | sed 's/"/\\"/g' | xargs)
        if [ "$EXP_FIRST" = true ]; then EXP_FIRST=false; else EXPERIMENTS_JSON="${EXPERIMENTS_JSON}, "; fi
        EXPERIMENTS_JSON="${EXPERIMENTS_JSON}\"${ename_clean}\""
    done <<< "$EXP_NAMES_RAW"
    EXPERIMENTS_JSON="${EXPERIMENTS_JSON}]"
fi

# ---- Tasks in Experiment 1 (sgRNA Library Synthesis) ----
OLIGO_ID=""
PCR_ID=""
CLONING_ID=""
EXP1_TASK_COUNT=0
EXP1_TASKS_JSON="[]"

if [ "$EXP1_FOUND" = "true" ] && [ -n "$EXP1_ID" ]; then
    EXP1_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXP1_ID} AND archived=false;" | tr -d '[:space:]')

    OLIGO_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP1_ID} AND LOWER(name) LIKE '%oligo%design%' AND archived=false LIMIT 1;")
    [ -n "$OLIGO_DATA" ] && OLIGO_ID=$(echo "$OLIGO_DATA" | tr -d '[:space:]')

    PCR_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP1_ID} AND LOWER(name) LIKE '%pcr%amplif%' AND archived=false LIMIT 1;")
    [ -n "$PCR_DATA" ] && PCR_ID=$(echo "$PCR_DATA" | tr -d '[:space:]')

    CLONING_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP1_ID} AND LOWER(name) LIKE '%library%clon%' AND archived=false LIMIT 1;")
    [ -n "$CLONING_DATA" ] && CLONING_ID=$(echo "$CLONING_DATA" | tr -d '[:space:]')

    TNAMES_1=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXP1_ID} AND archived=false;")
    EXP1_TASKS_JSON="["
    T1_FIRST=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$T1_FIRST" = true ]; then T1_FIRST=false; else EXP1_TASKS_JSON="${EXP1_TASKS_JSON}, "; fi
        EXP1_TASKS_JSON="${EXP1_TASKS_JSON}\"${tname_c}\""
    done <<< "$TNAMES_1"
    EXP1_TASKS_JSON="${EXP1_TASKS_JSON}]"
fi

# ---- Tasks in Experiment 2 (Cell Line Engineering) ----
LENTI_ID=""
TRANS_ID=""
EXP2_TASK_COUNT=0
EXP2_TASKS_JSON="[]"

if [ "$EXP2_FOUND" = "true" ] && [ -n "$EXP2_ID" ]; then
    EXP2_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXP2_ID} AND archived=false;" | tr -d '[:space:]')

    LENTI_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP2_ID} AND LOWER(name) LIKE '%lentiviral%prod%' AND archived=false LIMIT 1;")
    [ -n "$LENTI_DATA" ] && LENTI_ID=$(echo "$LENTI_DATA" | tr -d '[:space:]')

    TRANS_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP2_ID} AND LOWER(name) LIKE '%cell%transduct%' AND archived=false LIMIT 1;")
    [ -n "$TRANS_DATA" ] && TRANS_ID=$(echo "$TRANS_DATA" | tr -d '[:space:]')

    TNAMES_2=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXP2_ID} AND archived=false;")
    EXP2_TASKS_JSON="["
    T2_FIRST=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$T2_FIRST" = true ]; then T2_FIRST=false; else EXP2_TASKS_JSON="${EXP2_TASKS_JSON}, "; fi
        EXP2_TASKS_JSON="${EXP2_TASKS_JSON}\"${tname_c}\""
    done <<< "$TNAMES_2"
    EXP2_TASKS_JSON="${EXP2_TASKS_JSON}]"
fi

# ---- Check task connections ----
CONN_OLIGO_PCR="false"
CONN_PCR_CLONING="false"
CONN_LENTI_TRANS="false"

if [ -n "$OLIGO_ID" ] && [ -n "$PCR_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${OLIGO_ID} AND input_id=${PCR_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_OLIGO_PCR="true"
fi

if [ -n "$PCR_ID" ] && [ -n "$CLONING_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${PCR_ID} AND input_id=${CLONING_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_PCR_CLONING="true"
fi

if [ -n "$LENTI_ID" ] && [ -n "$TRANS_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${LENTI_ID} AND input_id=${TRANS_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_LENTI_TRANS="true"
fi

# ---- Protocol steps for Lentiviral Production ----
LENTI_STEP_COUNT=0
if [ -n "$LENTI_ID" ]; then
    PROTO_ID=$(scinote_db_query "SELECT id FROM protocols WHERE my_module_id=${LENTI_ID} LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PROTO_ID" ]; then
        LENTI_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')
    fi
fi

# ---- Find inventory ----
REPO_DATA=$(scinote_db_query "SELECT id, name FROM repositories WHERE LOWER(TRIM(name)) LIKE LOWER('%crispr%screen%reagent%') LIMIT 1;")
REPO_FOUND="false"
REPO_ID=""
REPO_NAME=""
COLUMN_COUNT=0
ITEM_COUNT=0
COLUMNS_JSON="[]"
ITEMS_JSON="[]"

if [ -n "$REPO_DATA" ]; then
    REPO_FOUND="true"
    REPO_ID=$(echo "$REPO_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
    REPO_NAME=$(echo "$REPO_DATA" | cut -d'|' -f2 | xargs)

    COLUMN_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    COL_NAMES=$(scinote_db_query "SELECT name FROM repository_columns WHERE repository_id=${REPO_ID} ORDER BY id;")
    COLUMNS_JSON="["
    COL_FIRST=true
    while IFS= read -r cname; do
        [ -z "$cname" ] && continue
        cname_c=$(echo "$cname" | sed 's/"/\\"/g' | xargs)
        if [ "$COL_FIRST" = true ]; then COL_FIRST=false; else COLUMNS_JSON="${COLUMNS_JSON}, "; fi
        COLUMNS_JSON="${COLUMNS_JSON}\"${cname_c}\""
    done <<< "$COL_NAMES"
    COLUMNS_JSON="${COLUMNS_JSON}]"

    ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
    ITEM_NAMES=$(scinote_db_query "SELECT name FROM repository_rows WHERE repository_id=${REPO_ID} ORDER BY id;")
    ITEMS_JSON="["
    ITEM_FIRST=true
    while IFS= read -r iname; do
        [ -z "$iname" ] && continue
        iname_c=$(echo "$iname" | sed 's/"/\\"/g' | xargs)
        if [ "$ITEM_FIRST" = true ]; then ITEM_FIRST=false; else ITEMS_JSON="${ITEMS_JSON}, "; fi
        ITEMS_JSON="${ITEMS_JSON}\"${iname_c}\""
    done <<< "$ITEM_NAMES"
    ITEMS_JSON="${ITEMS_JSON}]"
fi

PROJECT_NAME_ESC=$(json_escape "$PROJECT_NAME")
REPO_NAME_ESC=$(json_escape "$REPO_NAME")

RESULT_JSON=$(cat << JSONEOF
{
    "project_found": ${PROJECT_FOUND},
    "project_name": "${PROJECT_NAME_ESC}",
    "project_id": "${PROJECT_ID}",
    "experiment_sgrna_found": ${EXP1_FOUND},
    "experiment_sgrna_id": "${EXP1_ID}",
    "experiment_cell_found": ${EXP2_FOUND},
    "experiment_cell_id": "${EXP2_ID}",
    "experiments": ${EXPERIMENTS_JSON},
    "exp1_task_count": ${EXP1_TASK_COUNT:-0},
    "exp1_tasks": ${EXP1_TASKS_JSON},
    "exp2_task_count": ${EXP2_TASK_COUNT:-0},
    "exp2_tasks": ${EXP2_TASKS_JSON},
    "task_oligo_id": "${OLIGO_ID}",
    "task_pcr_id": "${PCR_ID}",
    "task_cloning_id": "${CLONING_ID}",
    "task_lenti_id": "${LENTI_ID}",
    "task_trans_id": "${TRANS_ID}",
    "conn_oligo_to_pcr": ${CONN_OLIGO_PCR},
    "conn_pcr_to_cloning": ${CONN_PCR_CLONING},
    "conn_lenti_to_transduction": ${CONN_LENTI_TRANS},
    "lentiviral_protocol_step_count": ${LENTI_STEP_COUNT:-0},
    "inventory_found": ${REPO_FOUND},
    "inventory_name": "${REPO_NAME_ESC}",
    "inventory_column_count": ${COLUMN_COUNT:-0},
    "inventory_columns": ${COLUMNS_JSON},
    "inventory_item_count": ${ITEM_COUNT:-0},
    "inventory_items": ${ITEMS_JSON},
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF
)

safe_write_json "/tmp/crispr_knockout_screen_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/crispr_knockout_screen_result.json"
cat /tmp/crispr_knockout_screen_result.json
echo "=== Export complete ==="
