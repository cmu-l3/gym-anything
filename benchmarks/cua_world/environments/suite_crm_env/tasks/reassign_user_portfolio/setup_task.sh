#!/bin/bash
echo "=== Setting up reassign_user_portfolio task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Clean up any existing conflicting users or records (idempotency)
suitecrm_db_query "DELETE FROM users WHERE id IN ('user_amercer_001', 'user_jhayes_002', 'user_treed_003');"
suitecrm_db_query "DELETE FROM accounts WHERE id LIKE 'acc_alex_%' OR id LIKE 'acc_taylor_%';"
suitecrm_db_query "DELETE FROM opportunities WHERE id LIKE 'opp_alex_%' OR id LIKE 'opp_taylor_%';"

# 2. Inject target Users
echo "Injecting users..."
suitecrm_db_query "INSERT INTO users (id, user_name, first_name, last_name, status, employee_status, deleted, date_entered, date_modified) VALUES 
('user_amercer_001', 'amercer', 'Alex', 'Mercer', 'Active', 'Active', 0, NOW(), NOW()),
('user_jhayes_002', 'jhayes', 'Jordan', 'Hayes', 'Active', 'Active', 0, NOW(), NOW()),
('user_treed_003', 'treed', 'Taylor', 'Reed', 'Active', 'Active', 0, NOW(), NOW());"

# 3. Inject Accounts assigned to Alex (Target) and Taylor (Control)
echo "Injecting accounts..."
suitecrm_db_query "INSERT INTO accounts (id, name, assigned_user_id, deleted, date_entered, date_modified) VALUES 
('acc_alex_1', 'Alpha Industries', 'user_amercer_001', 0, NOW(), NOW()),
('acc_alex_2', 'Bravo Corp', 'user_amercer_001', 0, NOW(), NOW()),
('acc_alex_3', 'Charlie Logistics', 'user_amercer_001', 0, NOW(), NOW()),
('acc_alex_4', 'Delta Dynamics', 'user_amercer_001', 0, NOW(), NOW()),
('acc_alex_5', 'Echo Systems', 'user_amercer_001', 0, NOW(), NOW()),
('acc_taylor_1', 'Tango Tech', 'user_treed_003', 0, NOW(), NOW()),
('acc_taylor_2', 'Uniform Utilities', 'user_treed_003', 0, NOW(), NOW()),
('acc_taylor_3', 'Victor Ventures', 'user_treed_003', 0, NOW(), NOW());"

# 4. Inject Opportunities assigned to Alex (Target) and Taylor (Control)
echo "Injecting opportunities..."
suitecrm_db_query "INSERT INTO opportunities (id, name, assigned_user_id, deleted, date_entered, date_modified) VALUES 
('opp_alex_1', 'Alpha Q3 Upgrade', 'user_amercer_001', 0, NOW(), NOW()),
('opp_alex_2', 'Bravo Expansion', 'user_amercer_001', 0, NOW(), NOW()),
('opp_alex_3', 'Charlie Fleet Renewal', 'user_amercer_001', 0, NOW(), NOW()),
('opp_alex_4', 'Delta Contract', 'user_amercer_001', 0, NOW(), NOW()),
('opp_alex_5', 'Echo Software License', 'user_amercer_001', 0, NOW(), NOW()),
('opp_taylor_1', 'Tango SaaS Renew', 'user_treed_003', 0, NOW(), NOW()),
('opp_taylor_2', 'Uniform Hardware', 'user_treed_003', 0, NOW(), NOW()),
('opp_taylor_3', 'Victor Consulting', 'user_treed_003', 0, NOW(), NOW());"

# 5. Ensure Firefox is running and navigated to SuiteCRM Home
echo "Ensuring application is ready..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="