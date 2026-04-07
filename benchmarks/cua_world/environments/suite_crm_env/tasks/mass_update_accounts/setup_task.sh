#!/bin/bash
set -e
echo "=== Setting up mass_update_accounts task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Clean previous task artifacts and reset existing Technology accounts
echo "Cleaning up database..."
suitecrm_db_query "DELETE FROM accounts WHERE id LIKE 'massupd-%'" 2>/dev/null || true
suitecrm_db_query "UPDATE accounts SET industry='Other' WHERE industry='Technology' AND deleted=0" 2>/dev/null || true
sleep 1

# 3. Insert 6 Technology accounts with non-Hot ratings
echo "Inserting 6 Technology accounts..."
suitecrm_db_query "INSERT INTO accounts (id, name, industry, rating, account_type, phone_office, billing_address_city, billing_address_state, billing_address_country, date_entered, date_modified, created_by, modified_user_id, assigned_user_id, deleted, description) VALUES
('massupd-tech-0001', 'Quantum Cloud Solutions', 'Technology', 'Cold', 'Prospect', '415-555-0101', 'San Francisco', 'CA', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'Cloud infrastructure provider'),
('massupd-tech-0002', 'NexGen Data Systems', 'Technology', 'Warm', 'Prospect', '512-555-0202', 'Austin', 'TX', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'Enterprise data management'),
('massupd-tech-0003', 'CyberPeak Innovations', 'Technology', 'Cold', 'Analyst', '206-555-0303', 'Seattle', 'WA', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'Cybersecurity solutions'),
('massupd-tech-0004', 'TeraByte Analytics Corp', 'Technology', 'Warm', 'Prospect', '617-555-0404', 'Boston', 'MA', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'Big data analytics tools'),
('massupd-tech-0005', 'Photon Semiconductor Inc', 'Technology', '', 'Other', '408-555-0505', 'San Jose', 'CA', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'Semiconductor design'),
('massupd-tech-0006', 'VertexAI Technologies', 'Technology', 'Cold', 'Prospect', '303-555-0606', 'Denver', 'CO', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'AI/ML predictive analytics');"

# 4. Insert 2 control (non-Technology) accounts
echo "Inserting control accounts..."
suitecrm_db_query "INSERT INTO accounts (id, name, industry, rating, account_type, phone_office, billing_address_city, billing_address_state, billing_address_country, date_entered, date_modified, created_by, modified_user_id, assigned_user_id, deleted, description) VALUES
('massupd-ctrl-0001', 'Ironforge Manufacturing Ltd', 'Manufacturing', 'Warm', 'Customer', '313-555-0701', 'Detroit', 'MI', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'Heavy industrial manufacturing'),
('massupd-ctrl-0002', 'Pinnacle Financial Group', 'Finance', 'Cold', 'Prospect', '212-555-0802', 'New York', 'NY', 'USA', NOW(), NOW(), '1', '1', '1', 0, 'Investment banking');"

# 5. Record initial state snapshots
echo "Recording initial non-Technology ratings..."
suitecrm_db_query "SELECT id, IFNULL(rating,'') FROM accounts WHERE (industry != 'Technology' OR industry IS NULL) AND deleted=0 ORDER BY id" > /tmp/initial_non_tech_ratings.txt

# 6. Ensure Firefox is logged in and navigate to the Home dashboard
echo "Ensuring SuiteCRM is logged in..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="