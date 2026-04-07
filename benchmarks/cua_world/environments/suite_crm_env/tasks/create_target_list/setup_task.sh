#!/bin/bash
set -e
echo "=== Setting up create_target_list task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous task artifacts to ensure clean state
suitecrm_db_query "DELETE plp FROM prospect_lists_prospects plp JOIN prospect_lists pl ON pl.id = plp.prospect_list_id WHERE pl.name='Q1 2025 Enterprise Outreach'" 2>/dev/null || true
suitecrm_db_query "UPDATE prospect_lists SET deleted=1 WHERE name='Q1 2025 Enterprise Outreach'" 2>/dev/null || true

# 2. Record initial target list count
INITIAL_TL_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM prospect_lists WHERE deleted=0" | tr -d '[:space:]')
echo "$INITIAL_TL_COUNT" > /tmp/initial_target_list_count.txt
echo "Initial target list count: $INITIAL_TL_COUNT"

# 3. Create test accounts for realism
echo "--- Seeding required accounts and contacts ---"
suitecrm_db_query "
INSERT INTO accounts (id, name, industry, account_type, date_entered, date_modified, deleted)
VALUES 
('acc-tl-ent-001', 'Acme Industrial Corp', 'Manufacturing', 'Customer', NOW(), NOW(), 0)
ON DUPLICATE KEY UPDATE name='Acme Industrial Corp', deleted=0;
"
suitecrm_db_query "
INSERT INTO accounts (id, name, industry, account_type, date_entered, date_modified, deleted)
VALUES 
('acc-tl-ent-002', 'TechGlobal Solutions', 'Technology', 'Customer', NOW(), NOW(), 0)
ON DUPLICATE KEY UPDATE name='TechGlobal Solutions', deleted=0;
"
suitecrm_db_query "
INSERT INTO accounts (id, name, industry, account_type, date_entered, date_modified, deleted)
VALUES 
('acc-tl-ent-003', 'Pacific Northwest Manufacturing', 'Manufacturing', 'Customer', NOW(), NOW(), 0)
ON DUPLICATE KEY UPDATE name='Pacific Northwest Manufacturing', deleted=0;
"

# 4. Create required contacts
suitecrm_db_query "
INSERT INTO contacts (id, first_name, last_name, title, date_entered, date_modified, deleted)
VALUES 
('con-tl-001', 'Margaret', 'Chen', 'VP of Procurement', NOW(), NOW(), 0)
ON DUPLICATE KEY UPDATE first_name='Margaret', last_name='Chen', deleted=0;
"
suitecrm_db_query "
INSERT INTO contacts (id, first_name, last_name, title, date_entered, date_modified, deleted)
VALUES 
('con-tl-002', 'David', 'Rodriguez', 'IT Director', NOW(), NOW(), 0)
ON DUPLICATE KEY UPDATE first_name='David', last_name='Rodriguez', deleted=0;
"
suitecrm_db_query "
INSERT INTO contacts (id, first_name, last_name, title, date_entered, date_modified, deleted)
VALUES 
('con-tl-003', 'Sarah', 'Williams', 'Operations Manager', NOW(), NOW(), 0)
ON DUPLICATE KEY UPDATE first_name='Sarah', last_name='Williams', deleted=0;
"

# 5. Link contacts to accounts
suitecrm_db_query "
INSERT INTO accounts_contacts (id, contact_id, account_id, date_modified, deleted)
VALUES ('ac-tl-rel-001', 'con-tl-001', 'acc-tl-ent-001', NOW(), 0)
ON DUPLICATE KEY UPDATE deleted=0;
"
suitecrm_db_query "
INSERT INTO accounts_contacts (id, contact_id, account_id, date_modified, deleted)
VALUES ('ac-tl-rel-002', 'con-tl-002', 'acc-tl-ent-002', NOW(), 0)
ON DUPLICATE KEY UPDATE deleted=0;
"
suitecrm_db_query "
INSERT INTO accounts_contacts (id, contact_id, account_id, date_modified, deleted)
VALUES ('ac-tl-rel-003', 'con-tl-003', 'acc-tl-ent-003', NOW(), 0)
ON DUPLICATE KEY UPDATE deleted=0;
"

# 6. Ensure logged in and navigate to Target Lists module
echo "Navigating to SuiteCRM Target Lists module..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=ProspectLists&action=index"
sleep 4

# 7. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="