#!/bin/bash
echo "=== Setting up document_reagent_prep_workflow task ==="

# Clean up previous task files
rm -f /tmp/reagent_prep_result.json 2>/dev/null || true
rm -f /tmp/initial_stock_count 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create prerequisite data via SQL
echo "=== Creating prerequisite Projects, Experiments, and Inventories ==="

# 1. Create Project
PROJ_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM projects WHERE name='General Lab Support';" | tr -d '[:space:]')
if [ "${PROJ_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('General Lab Support', 1, 1, 1, NOW(), NOW(), false, false, false);"
fi
PROJECT_ID=$(scinote_db_query "SELECT id FROM projects WHERE name='General Lab Support' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Project" "$PROJECT_ID"

# 2. Create Experiment
EXP_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM experiments WHERE name='Buffer Preparation' AND project_id=${PROJECT_ID};" | tr -d '[:space:]')
if [ "${EXP_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Buffer Preparation', ${PROJECT_ID}, 1, 1, false, false, NOW(), NOW(), gen_random_uuid());"
fi
EXPERIMENT_ID=$(scinote_db_query "SELECT id FROM experiments WHERE name='Buffer Preparation' AND project_id=${PROJECT_ID} LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Experiment" "$EXPERIMENT_ID"

# 3. Create 'Chemical Storage' Inventory and Ingredients
CHEM_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM repositories WHERE name='Chemical Storage';" | tr -d '[:space:]')
if [ "${CHEM_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO repositories (name, team_id, created_by_id, created_at, updated_at, archived) VALUES ('Chemical Storage', 1, 1, NOW(), NOW(), false);"
    CHEM_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='Chemical Storage' LIMIT 1;" | tr -d '[:space:]')
    ensure_user_assignment "Repository" "$CHEM_ID"
    
    for item in "Sodium Chloride (NaCl)" "Potassium Chloride (KCl)" "Disodium Phosphate (Na2HPO4)" "Monopotassium Phosphate (KH2PO4)"; do
        scinote_db_query "INSERT INTO repository_rows (name, repository_id, created_by_id, created_at, updated_at) VALUES ('$item', ${CHEM_ID}, 1, NOW(), NOW());"
    done
fi

# 4. Create 'Stock Solutions' Inventory (Empty)
STOCK_EXISTS=$(scinote_db_query "SELECT COUNT(*) FROM repositories WHERE name='Stock Solutions';" | tr -d '[:space:]')
if [ "${STOCK_EXISTS:-0}" = "0" ]; then
    scinote_db_query "INSERT INTO repositories (name, team_id, created_by_id, created_at, updated_at, archived) VALUES ('Stock Solutions', 1, 1, NOW(), NOW(), false);"
fi
STOCK_ID=$(scinote_db_query "SELECT id FROM repositories WHERE name='Stock Solutions' LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "Repository" "$STOCK_ID"

# Record initial count of items in Stock Solutions
INITIAL_STOCK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id=${STOCK_ID};" | tr -d '[:space:]')
echo "${INITIAL_STOCK_COUNT:-0}" > /tmp/initial_stock_count
echo "Initial stock item count: ${INITIAL_STOCK_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="