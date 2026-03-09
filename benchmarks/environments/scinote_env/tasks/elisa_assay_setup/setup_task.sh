#!/bin/bash
echo "=== Setting up elisa_assay_setup task ==="

rm -f /tmp/elisa_assay_setup_result.json 2>/dev/null || true
rm -f /tmp/elisa_initial_counts.json 2>/dev/null || true
rm -f /tmp/elisa_repo_id 2>/dev/null || true

source /workspace/scripts/task_utils.sh

# ---- Create pre-seeded project ----
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='ELISA Assay Development - IL-6';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('ELISA Assay Development - IL-6', 1, 1, 1, NOW(), NOW(), false, false, false);"
    echo "Created project"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='ELISA Assay Development - IL-6' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# ---- Create pre-seeded inventory with 2 columns but no items ----
REPO_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM repositories WHERE name='ELISA Consumables' AND team_id=1;" | tr -d '[:space:]')
if [ "${REPO_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO repositories (name, team_id, created_by_id, created_at, updated_at, archived) VALUES ('ELISA Consumables', 1, 1, NOW(), NOW(), false);"
    echo "Created inventory 'ELISA Consumables'"
fi
REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='ELISA Consumables' AND team_id=1 LIMIT 1;" | tr -d '[:space:]')
echo "$REPO_ID" > /tmp/elisa_repo_id

# Add pre-seeded columns if not present
for colname in "Supplier" "Catalog Number"; do
    COL_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID} AND name='${colname}';" | tr -d '[:space:]')
    if [ "${COL_EXISTS:-0}" = "0" ]; then
        # data_type 1 = text
        scinote_db_query "INSERT INTO repository_columns (name, data_type, repository_id, created_by_id, created_at, updated_at) VALUES ('${colname}', 1, ${REPO_ID}, 1, NOW(), NOW());"
        echo "Created column '${colname}'"
    fi
done

# ---- Record baseline counts ----
INITIAL_EXP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE project_id=${PROJECT_ID};" | tr -d '[:space:]')
INITIAL_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules mm JOIN experiments e ON mm.experiment_id=e.id WHERE e.project_id=${PROJECT_ID} AND mm.archived=false;" | tr -d '[:space:]')
INITIAL_COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')
INITIAL_ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${REPO_ID};" | tr -d '[:space:]')

safe_write_json "/tmp/elisa_initial_counts.json" "{\"experiments\": ${INITIAL_EXP_COUNT:-0}, \"tasks\": ${INITIAL_TASK_COUNT:-0}, \"columns\": ${INITIAL_COL_COUNT:-0}, \"items\": ${INITIAL_ITEM_COUNT:-0}}"
echo "Baseline: experiments=${INITIAL_EXP_COUNT}, tasks=${INITIAL_TASK_COUNT}, columns=${INITIAL_COL_COUNT}, items=${INITIAL_ITEM_COUNT}"

ensure_firefox_running "${SCINOTE_URL}/users/sign_in"
sleep 3
take_screenshot /tmp/elisa_assay_setup_start_screenshot.png

echo "=== Setup complete: Create experiment, 4 tasks, connect them, add protocol, expand inventory ==="
