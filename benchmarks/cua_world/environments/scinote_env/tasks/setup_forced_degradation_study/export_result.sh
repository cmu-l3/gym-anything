#!/bin/bash
echo "=== Exporting setup_forced_degradation_study result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/forced_degradation_end_screenshot.png

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================
# 1. Find the target project
# ==============================================================
PROJECT_DATA=$(scinote_db_query "SELECT id, name FROM projects WHERE LOWER(TRIM(name)) LIKE LOWER('%ibuprofen%forced%degrad%') LIMIT 1;")
PROJECT_FOUND="false"
PROJECT_ID=""
PROJECT_NAME=""

if [ -n "$PROJECT_DATA" ]; then
    PROJECT_FOUND="true"
    PROJECT_ID=$(echo "$PROJECT_DATA" | cut -d'|' -f1 | tr -d '[:space:]')
    PROJECT_NAME=$(echo "$PROJECT_DATA" | cut -d'|' -f2 | xargs)
fi

# ==============================================================
# 2. Find experiment in project
# ==============================================================
EXP_ID=""
EXP_FOUND="false"

if [ -n "$PROJECT_ID" ]; then
    EXP_DATA=$(scinote_db_query "SELECT id FROM experiments WHERE project_id=${PROJECT_ID} AND LOWER(name) LIKE '%stress%test%panel%' LIMIT 1;")
    if [ -n "$EXP_DATA" ]; then
        EXP_FOUND="true"
        EXP_ID=$(echo "$EXP_DATA" | tr -d '[:space:]')
    fi
fi

# ==============================================================
# 3. Find all 5 tasks in the experiment
# ==============================================================
STOCK_ID=""
ACID_ID=""
BASE_ID=""
OXI_ID=""
HPLC_ID=""
TASK_COUNT=0
TASKS_JSON="[]"

if [ "$EXP_FOUND" = "true" ] && [ -n "$EXP_ID" ]; then
    TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXP_ID} AND archived=false;" | tr -d '[:space:]')

    STOCK_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP_ID} AND LOWER(name) LIKE '%stock%solution%prep%' AND archived=false LIMIT 1;")
    [ -n "$STOCK_DATA" ] && STOCK_ID=$(echo "$STOCK_DATA" | tr -d '[:space:]')

    ACID_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP_ID} AND LOWER(name) LIKE '%acid%hydro%' AND archived=false LIMIT 1;")
    [ -n "$ACID_DATA" ] && ACID_ID=$(echo "$ACID_DATA" | tr -d '[:space:]')

    BASE_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP_ID} AND LOWER(name) LIKE '%base%hydro%' AND archived=false LIMIT 1;")
    [ -n "$BASE_DATA" ] && BASE_ID=$(echo "$BASE_DATA" | tr -d '[:space:]')

    OXI_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP_ID} AND LOWER(name) LIKE '%oxidat%stress%' AND archived=false LIMIT 1;")
    [ -n "$OXI_DATA" ] && OXI_ID=$(echo "$OXI_DATA" | tr -d '[:space:]')

    HPLC_DATA=$(scinote_db_query "SELECT id FROM my_modules WHERE experiment_id=${EXP_ID} AND LOWER(name) LIKE '%hplc%purity%' AND archived=false LIMIT 1;")
    [ -n "$HPLC_DATA" ] && HPLC_ID=$(echo "$HPLC_DATA" | tr -d '[:space:]')

    # Collect all task names for JSON
    TNAMES=$(scinote_db_query "SELECT name FROM my_modules WHERE experiment_id=${EXP_ID} AND archived=false;")
    TASKS_JSON="["
    T_FIRST=true
    while IFS= read -r tname; do
        [ -z "$tname" ] && continue
        tname_c=$(echo "$tname" | sed 's/"/\\"/g' | xargs)
        if [ "$T_FIRST" = true ]; then T_FIRST=false; else TASKS_JSON="${TASKS_JSON}, "; fi
        TASKS_JSON="${TASKS_JSON}\"${tname_c}\""
    done <<< "$TNAMES"
    TASKS_JSON="${TASKS_JSON}]"
fi

# ==============================================================
# 4. Check 6 connections (fan-out/fan-in)
# ==============================================================
CONN_STOCK_ACID="false"
CONN_STOCK_BASE="false"
CONN_STOCK_OXI="false"
CONN_ACID_HPLC="false"
CONN_BASE_HPLC="false"
CONN_OXI_HPLC="false"

# Fan-out: Stock -> Acid, Base, Oxidative
if [ -n "$STOCK_ID" ] && [ -n "$ACID_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${STOCK_ID} AND input_id=${ACID_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_STOCK_ACID="true"
fi

if [ -n "$STOCK_ID" ] && [ -n "$BASE_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${STOCK_ID} AND input_id=${BASE_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_STOCK_BASE="true"
fi

if [ -n "$STOCK_ID" ] && [ -n "$OXI_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${STOCK_ID} AND input_id=${OXI_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_STOCK_OXI="true"
fi

# Fan-in: Acid, Base, Oxidative -> HPLC
if [ -n "$ACID_ID" ] && [ -n "$HPLC_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${ACID_ID} AND input_id=${HPLC_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_ACID_HPLC="true"
fi

if [ -n "$BASE_ID" ] && [ -n "$HPLC_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${BASE_ID} AND input_id=${HPLC_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_BASE_HPLC="true"
fi

if [ -n "$OXI_ID" ] && [ -n "$HPLC_ID" ]; then
    CNT=$(scinote_db_query "SELECT COUNT(*) FROM connections WHERE output_id=${OXI_ID} AND input_id=${HPLC_ID};" | tr -d '[:space:]')
    [ "${CNT:-0}" -gt "0" ] && CONN_OXI_HPLC="true"
fi

# ==============================================================
# 5. Protocol steps on Stock Solution Preparation
# ==============================================================
PROTOCOL_STEP_COUNT=0
PROTOCOL_STEPS_JSON="[]"

if [ -n "$STOCK_ID" ]; then
    PROTO_ID=$(scinote_db_query "SELECT id FROM protocols WHERE my_module_id=${STOCK_ID} LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$PROTO_ID" ]; then
        PROTOCOL_STEP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM steps WHERE protocol_id=${PROTO_ID};" | tr -d '[:space:]')

        STEPS_DATA=$(scinote_db_query "SELECT id, name, position FROM steps WHERE protocol_id=${PROTO_ID} ORDER BY position;")
        if [ -n "$STEPS_DATA" ]; then
            PROTOCOL_STEPS_JSON="["
            S_FIRST=true
            while IFS='|' read -r step_id step_name step_position; do
                [ -z "$step_id" ] && continue
                step_name_clean=$(json_escape "$step_name")

                # Extract rich text from step
                STEP_TEXT=$(scinote_db_query "SELECT st.text FROM step_texts st JOIN step_orderable_elements soe ON soe.orderable_type='StepText' AND soe.orderable_id=st.id WHERE soe.step_id=${step_id} LIMIT 1;" 2>/dev/null | head -1)
                if [ -z "$STEP_TEXT" ]; then
                    STEP_TEXT=$(scinote_db_query "SELECT text FROM step_texts WHERE step_id=${step_id} LIMIT 1;" 2>/dev/null | head -1)
                fi
                STEP_TEXT_PLAIN=$(echo "$STEP_TEXT" | sed -e 's/<[^>]*>//g' | sed 's/&nbsp;/ /g' | xargs)
                STEP_TEXT_CLEAN=$(json_escape "$STEP_TEXT_PLAIN")

                if [ "$S_FIRST" = true ]; then S_FIRST=false; else PROTOCOL_STEPS_JSON="${PROTOCOL_STEPS_JSON}, "; fi
                PROTOCOL_STEPS_JSON="${PROTOCOL_STEPS_JSON}{\"id\": \"${step_id}\", \"name\": \"${step_name_clean}\", \"position\": ${step_position:-0}, \"text_content\": \"${STEP_TEXT_CLEAN}\"}"
            done <<< "$STEPS_DATA"
            PROTOCOL_STEPS_JSON="${PROTOCOL_STEPS_JSON}]"
        fi
    fi
fi

# ==============================================================
# 6. Find inventory
# ==============================================================
REPO_DATA=$(scinote_db_query "SELECT id, name FROM repositories WHERE LOWER(TRIM(name)) LIKE LOWER('%degrad%reagent%') LIMIT 1;")
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

# ==============================================================
# 7. Check inventory-to-task assignments
# ==============================================================
ASSIGNED_COUNT=0
ASSIGNED_ITEMS_JSON="[]"

if [ -n "$STOCK_ID" ]; then
    # Try multiple table structures for inventory assignments
    ASSIGN_IDS=$(scinote_db_query "SELECT repository_row_id FROM assigned_repository_rows WHERE assignable_id=${STOCK_ID} AND assignable_type='MyModule';" 2>/dev/null)
    if [ -z "$ASSIGN_IDS" ]; then
        ASSIGN_IDS=$(scinote_db_query "SELECT repository_row_id FROM my_module_repository_rows WHERE my_module_id=${STOCK_ID};" 2>/dev/null)
    fi

    if [ -n "$ASSIGN_IDS" ]; then
        ASSIGNED_ITEMS_JSON="["
        A_FIRST=true
        while IFS= read -r rr_id; do
            rr_id=$(echo "$rr_id" | tr -d '[:space:]')
            [ -z "$rr_id" ] && continue

            RR_NAME=$(scinote_db_query "SELECT name FROM repository_rows WHERE id=${rr_id};" | tr -d '\n')
            RR_NAME_CLEAN=$(json_escape "$RR_NAME")

            if [ "$A_FIRST" = true ]; then A_FIRST=false; else ASSIGNED_ITEMS_JSON="${ASSIGNED_ITEMS_JSON}, "; fi
            ASSIGNED_ITEMS_JSON="${ASSIGNED_ITEMS_JSON}\"${RR_NAME_CLEAN}\""
            ASSIGNED_COUNT=$((ASSIGNED_COUNT + 1))
        done <<< "$ASSIGN_IDS"
        ASSIGNED_ITEMS_JSON="${ASSIGNED_ITEMS_JSON}]"
    fi
fi

# ==============================================================
# 8. Check result text and smart annotation on HPLC task
# ==============================================================
RESULT_TEXT_COUNT=0
RICH_TEXT=""
HAS_RESULT_TEXT="false"

if [ -n "$HPLC_ID" ]; then
    RESULT_TEXT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM results WHERE my_module_id=${HPLC_ID} AND type='ResultText';" | tr -d '[:space:]')

    if [ "${RESULT_TEXT_COUNT:-0}" -gt "0" ]; then
        HAS_RESULT_TEXT="true"
        # Extract rich text body for smart annotation checking
        RICH_TEXT=$(scinote_db_query "SELECT body FROM action_text_rich_texts WHERE record_type='Result' AND record_id IN (SELECT id FROM results WHERE my_module_id=${HPLC_ID} AND type='ResultText');" 2>/dev/null | head -c 2000 | json_escape)

        if [ -z "$RICH_TEXT" ] || [ "$RICH_TEXT" = " " ]; then
            RICH_TEXT=$(scinote_db_query "SELECT text FROM result_texts WHERE result_id IN (SELECT id FROM results WHERE my_module_id=${HPLC_ID} AND type='ResultText');" 2>/dev/null | head -c 2000 | json_escape)
        fi
    fi
fi

# ==============================================================
# Build and write result JSON
# ==============================================================
PROJECT_NAME_ESC=$(json_escape "$PROJECT_NAME")
REPO_NAME_ESC=$(json_escape "$REPO_NAME")

RESULT_JSON=$(cat << JSONEOF
{
    "task_start_time": ${TASK_START_TIME},
    "project_found": ${PROJECT_FOUND},
    "project_name": "${PROJECT_NAME_ESC}",
    "project_id": "${PROJECT_ID}",
    "experiment_found": ${EXP_FOUND},
    "experiment_id": "${EXP_ID}",
    "task_count": ${TASK_COUNT:-0},
    "tasks": ${TASKS_JSON},
    "task_stock_id": "${STOCK_ID}",
    "task_acid_id": "${ACID_ID}",
    "task_base_id": "${BASE_ID}",
    "task_oxi_id": "${OXI_ID}",
    "task_hplc_id": "${HPLC_ID}",
    "conn_stock_to_acid": ${CONN_STOCK_ACID},
    "conn_stock_to_base": ${CONN_STOCK_BASE},
    "conn_stock_to_oxi": ${CONN_STOCK_OXI},
    "conn_acid_to_hplc": ${CONN_ACID_HPLC},
    "conn_base_to_hplc": ${CONN_BASE_HPLC},
    "conn_oxi_to_hplc": ${CONN_OXI_HPLC},
    "protocol_step_count": ${PROTOCOL_STEP_COUNT:-0},
    "protocol_steps": ${PROTOCOL_STEPS_JSON},
    "inventory_found": ${REPO_FOUND},
    "inventory_name": "${REPO_NAME_ESC}",
    "inventory_column_count": ${COLUMN_COUNT:-0},
    "inventory_columns": ${COLUMNS_JSON},
    "inventory_item_count": ${ITEM_COUNT:-0},
    "inventory_items": ${ITEMS_JSON},
    "assigned_count": ${ASSIGNED_COUNT},
    "assigned_items": ${ASSIGNED_ITEMS_JSON},
    "has_result_text": ${HAS_RESULT_TEXT},
    "result_text_count": ${RESULT_TEXT_COUNT:-0},
    "rich_text": "${RICH_TEXT}",
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF
)

safe_write_json "/tmp/forced_degradation_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/forced_degradation_result.json"
cat /tmp/forced_degradation_result.json
echo "=== Export complete ==="
