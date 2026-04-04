#!/bin/bash
echo "=== Setting up western_blot_workflow task ==="

rm -f /tmp/western_blot_workflow_result.json 2>/dev/null || true
rm -f /tmp/wb_experiment_id 2>/dev/null || true
rm -f /tmp/wb_initial_counts.json 2>/dev/null || true

source /workspace/scripts/task_utils.sh

# ---- Create pre-seeded project ----
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='Western Blot - p53 Expression Study';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Western Blot - p53 Expression Study', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='Western Blot - p53 Expression Study' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# ---- Create pre-seeded experiment ----
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='SDS-PAGE Workflow' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('SDS-PAGE Workflow', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
    echo "Created experiment"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='SDS-PAGE Workflow' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"
echo "$EXPERIMENT_ID" > /tmp/wb_experiment_id

# ---- Create pre-seeded tasks (Sample Preparation at far left, Detection at far right, disconnected) ----
for task_info in "Sample Preparation|0|200" "Detection and Imaging|900|200"; do
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

# ---- Record baseline counts ----
INITIAL_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules WHERE experiment_id=${EXPERIMENT_ID} AND archived=false;" | tr -d '[:space:]')
INITIAL_CONN_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM connections c JOIN my_modules mm ON (c.output_id=mm.id OR c.input_id=mm.id) WHERE mm.experiment_id=${EXPERIMENT_ID};" | tr -d '[:space:]')
INITIAL_REPO_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repositories;" | tr -d '[:space:]')

safe_write_json "/tmp/wb_initial_counts.json" "{\"tasks\": ${INITIAL_TASK_COUNT:-0}, \"connections\": ${INITIAL_CONN_COUNT:-0}, \"repositories\": ${INITIAL_REPO_COUNT:-0}}"
echo "Baseline: tasks=${INITIAL_TASK_COUNT}, connections=${INITIAL_CONN_COUNT}, repos=${INITIAL_REPO_COUNT}"

ensure_firefox_running "${SCINOTE_URL}/users/sign_in"
sleep 3
take_screenshot /tmp/western_blot_workflow_start_screenshot.png

echo "=== Setup complete: Add SDS-PAGE and Membrane Transfer tasks, connect all 4, add protocol, create inventory ==="
