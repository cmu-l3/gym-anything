#!/bin/bash
echo "=== Setting up privileged_access_audit_remediation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Setup Database State (Departments, Groups, Users, Asset)
echo "--- Injecting Vulnerable IAM State ---"

# Create Departments
snipeit_db_query "INSERT INTO departments (name, created_at, updated_at) VALUES 
('IT Administration', NOW(), NOW()), 
('HR', NOW(), NOW()), 
('Finance', NOW(), NOW()), 
('Operations', NOW(), NOW()), 
('External Contractors', NOW(), NOW())"

DEPT_IT=$(snipeit_db_query "SELECT id FROM departments WHERE name='IT Administration'" | tr -d '[:space:]')
DEPT_HR=$(snipeit_db_query "SELECT id FROM departments WHERE name='HR'" | tr -d '[:space:]')
DEPT_FIN=$(snipeit_db_query "SELECT id FROM departments WHERE name='Finance'" | tr -d '[:space:]')
DEPT_OPS=$(snipeit_db_query "SELECT id FROM departments WHERE name='Operations'" | tr -d '[:space:]')
DEPT_EXT=$(snipeit_db_query "SELECT id FROM departments WHERE name='External Contractors'" | tr -d '[:space:]')

# Move default admin to IT Administration
snipeit_db_query "UPDATE users SET department_id=$DEPT_IT WHERE username='admin'"

# Create the scoped Department Managers permission group
snipeit_db_query "INSERT INTO permission_groups (name, permissions, created_at, updated_at) VALUES 
('Department Managers', '{\"users.view\":\"1\",\"assets.view\":\"1\",\"reports.view\":\"1\"}', NOW(), NOW())"

# Create standard bcrypt password hash for seeded users
DUMMY_PW='$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'

# Inject Users (mix of legitimate admins, violating non-IT admins, and the rogue contractor)
snipeit_db_query "INSERT INTO users (first_name, last_name, username, email, password, activated, permissions, department_id, created_at, updated_at) VALUES
('John', 'Doe', 'jdoe', 'jdoe@example.com', '$DUMMY_PW', 1, '{\"superuser\":\"1\"}', $DEPT_IT, NOW(), NOW()),
('Alice', 'Smith', 'asmith', 'asmith@example.com', '$DUMMY_PW', 1, '{\"superuser\":\"1\"}', $DEPT_HR, NOW(), NOW()),
('Bob', 'Jones', 'bjones', 'bjones@example.com', '$DUMMY_PW', 1, '{\"superuser\":\"1\"}', $DEPT_FIN, NOW(), NOW()),
('Carol', 'Williams', 'cwilliams', 'cwilliams@example.com', '$DUMMY_PW', 1, '{\"superuser\":\"1\"}', $DEPT_OPS, NOW(), NOW()),
('Eric', 'Vance', 'evance', 'evance@example.com', '$DUMMY_PW', 1, '{\"reports.view\":\"1\"}', $DEPT_EXT, NOW(), NOW())"

sleep 2

# 3. Inject the Contractor's Hardware Asset via API to ensure proper relationship bindings
echo "--- Assigning Hardware ---"
MDL_ID=$(snipeit_db_query "SELECT id FROM models WHERE deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
SL_READY=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
EVANCE_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='evance' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

# Create Asset
ASSET_JSON=$(snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-EXT-01\",\"name\":\"Contractor Laptop\",\"model_id\":$MDL_ID,\"status_id\":$SL_READY}")
ASSET_ID=$(echo "$ASSET_JSON" | jq -r '.payload.id // .id // empty' 2>/dev/null)

if [ -n "$ASSET_ID" ]; then
    # Checkout Asset to evance
    snipeit_api POST "hardware/${ASSET_ID}/checkout" "{\"assigned_to\":$EVANCE_ID,\"checkout_to_type\":\"user\",\"note\":\"Initial contractor assignment\"}"
else
    # Fallback to DB if API fails
    SL_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Deployed' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, assigned_to, assigned_type, physical, created_at, updated_at) VALUES ('ASSET-EXT-01', 'Contractor Laptop', $MDL_ID, $SL_DEPLOYED, $EVANCE_ID, 'App\\\\Models\\\\User', 1, NOW(), NOW())"
fi

# 4. Clean up any previous run's report file
rm -f /home/ga/Desktop/access_remediation_report.txt

# 5. Launch UI
echo "--- Launching Snipe-IT ---"
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/users"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="