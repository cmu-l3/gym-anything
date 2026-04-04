#!/bin/bash
echo "=== Setting up cell_culture_drug_treatment task ==="

rm -f /tmp/cell_culture_drug_treatment_result.json 2>/dev/null || true
rm -f /tmp/cdt_experiment_id 2>/dev/null || true
rm -f /tmp/cdt_repo_id 2>/dev/null || true
rm -f /tmp/cdt_initial_counts.json 2>/dev/null || true

source /workspace/scripts/task_utils.sh

# ---- Create pre-seeded project ----
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='HeLa Cell Doxorubicin Dose Response';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('HeLa Cell Doxorubicin Dose Response', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='HeLa Cell Doxorubicin Dose Response' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# ---- Create pre-seeded experiment ----
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='Dose Response Analysis' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Dose Response Analysis', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
    echo "Created experiment"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Dose Response Analysis' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"
echo "$EXPERIMENT_ID" > /tmp/cdt_experiment_id

# ---- Create 2 pre-seeded tasks at widely spaced positions (not connected) ----
for task_info in "Cell Seeding|0|200" "Cell Viability Assay|900|200"; do
    TNAME=$(echo "$task_info" | cut -d'|' -f1)
    TX=$(echo "$task_info" | cut -d'|' -f2)
    TY=$(echo "$task_info" | cut -d'|' -f3)
    T_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE name='${TNAME}' AND experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
    if [ "${T_EXISTS:-0}" = "0" ]; then
        scinote_db_query "INSERT INTO my_modules (name, x, y, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('${TNAME}', ${TX}, ${TY}, ${EXPERIMENT_ID}, NOW(), NOW(), false, 0, 1);"
        TID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='${TNAME}' AND experiment_id=${EXPERIMENT_ID} LIMIT 1;" | tr -d '[:space:]')
        scinote_db_query "INSERT INTO protocols (my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES (${TID}, 1, 0, NOW(), NOW(), false);"
        ensure_user_assignment "MyModule" "$TID"
        echo "Created task '${TNAME}'"
    fi
done

# ---- Create pre-seeded inventory with 1 column, no items ----
REPO_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM repositories WHERE name='Drug Stocks' AND team_id=1;" | tr -d '[:space:]')
if [ "${REPO_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO repositories (name, team_id, created_by_id, created_at, updated_at, archived) VALUES ('Drug Stocks', 1, 1, NOW(), NOW(), false);"
    echo "Created inventory 'Drug Stocks'"
fi
REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='Drug Stocks' AND team_id=1 LIMIT 1;" | tr -d '[:space:]')
echo "$REPO_ID" > /tmp/cdt_repo_id

# Add pre-seeded column if not present
COL_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID} AND name='Concentration (μM)';" | tr -d '[:space:]')
if [ "${COL_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO repository_columns (name, data_type, repository_id, created_by_id, created_at, updated_at) VALUES ('Concentration (μM)', 1, ${REPO_ID}, 1, NOW(), NOW());"
    echo "Created column 'Concentration (μM)'"
fi

# ---- Record baseline counts ----
INITIAL_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;" | tr -d '[:space:]')
INITIAL_CONN_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM connections c JOIN my_modules mm ON (c.output_id=mm.id OR c.input_id=mm.id) WHERE mm.experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
INITIAL_COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
INITIAL_ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')

safe_write_json "/tmp/cdt_initial_counts.json" "{\"tasks\": ${INITIAL_TASK_COUNT:-0}, \"connections\": ${INITIAL_CONN_COUNT:-0}, \"columns\": ${INITIAL_COL_COUNT:-0}, \"items\": ${INITIAL_ITEM_COUNT:-0}}"
echo "Baseline: tasks=${INITIAL_TASK_COUNT}, connections=${INITIAL_CONN_COUNT}, columns=${INITIAL_COL_COUNT}, items=${INITIAL_ITEM_COUNT}"

ensure_firefox_running "${SCINOTE_URL}/users/sign_in"
sleep 3
take_screenshot /tmp/cell_culture_drug_treatment_start_screenshot.png

echo "=== Setup complete: Add Drug Treatment and Data Analysis tasks, connect all 4, add protocol, expand inventory ==="
