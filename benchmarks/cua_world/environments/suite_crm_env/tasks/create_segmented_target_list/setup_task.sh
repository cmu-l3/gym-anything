#!/bin/bash
echo "=== Setting up create_segmented_target_list task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean slate: Soft delete any existing target lists with the same name
suitecrm_db_query "UPDATE prospect_lists SET deleted=1 WHERE name='Seattle Regional Campaign';"

# 2. Prevent ambiguity: Change any existing default seeded contacts in Seattle to "Other"
suitecrm_db_query "UPDATE contacts SET primary_address_city = 'Other' WHERE primary_address_city = 'Seattle';"

# 3. Inject a precise, mixed-city contact dataset
echo "Injecting mixed-city contact dataset..."
suitecrm_db_query "INSERT INTO contacts (id, first_name, last_name, primary_address_city, title, date_entered, date_modified, modified_user_id, created_by, deleted) VALUES
(UUID(), 'Elena', 'Rostova', 'Seattle', 'Director of IT', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Marcus', 'Chen', 'Seattle', 'VP of Sales', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Sarah', 'Jenkins', 'Seattle', 'Operations Manager', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Michael', 'Chang', 'Seattle', 'CTO', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Jessica', 'Alba', 'Seattle', 'Marketing Lead', NOW(), NOW(), '1', '1', 0),
(UUID(), 'David', 'Miller', 'Portland', 'CEO', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Aisha', 'Patel', 'San Francisco', 'Developer', NOW(), NOW(), '1', '1', 0),
(UUID(), 'James', 'Wilson', 'Austin', 'Designer', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Maria', 'Garcia', 'Chicago', 'Product Manager', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Robert', 'Brown', 'New York', 'Analyst', NOW(), NOW(), '1', '1', 0),
(UUID(), 'William', 'Davis', 'Portland', 'HR Manager', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Linda', 'Martinez', 'San Francisco', 'Sales Rep', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Richard', 'Anderson', 'Austin', 'Support Tech', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Susan', 'Thomas', 'Chicago', 'Consultant', NOW(), NOW(), '1', '1', 0),
(UUID(), 'Joseph', 'Jackson', 'New York', 'Architect', NOW(), NOW(), '1', '1', 0);"

# 4. Ensure logged in and resting on the Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Create 'Seattle Regional Campaign' Target List and link the 5 Seattle contacts."