#!/bin/bash
echo "=== Setting up manage_event_delegates task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Delete existing event with this name if any
if suitecrm_db_query "SELECT id FROM fp_events WHERE name='VIP Executive Dinner 2026'" | grep -q "."; then
    echo "Cleaning up pre-existing event..."
    soft_delete_record "fp_events" "name='VIP Executive Dinner 2026'"
fi

# 3. Insert the 3 target contacts into the DB
# We inject these to ensure the search popup yields authentic, predictable results
echo "Seeding target contacts..."
suitecrm_db_query "INSERT INTO contacts (id, first_name, last_name, title, phone_work, date_entered, date_modified, deleted) VALUES ('c_1001_os', 'Olivia', 'Sterling', 'VP of Procurement', '(312) 555-0198', NOW(), NOW(), 0) ON DUPLICATE KEY UPDATE deleted=0;"
suitecrm_db_query "INSERT INTO contacts (id, first_name, last_name, title, phone_work, date_entered, date_modified, deleted) VALUES ('c_1002_jw', 'Jameson', 'Wright', 'Director of Operations', '(312) 555-0452', NOW(), NOW(), 0) ON DUPLICATE KEY UPDATE deleted=0;"
suitecrm_db_query "INSERT INTO contacts (id, first_name, last_name, title, phone_work, date_entered, date_modified, deleted) VALUES ('c_1003_er', 'Elena', 'Rostova', 'Chief Supply Chain Officer', '(312) 555-0871', NOW(), NOW(), 0) ON DUPLICATE KEY UPDATE deleted=0;"

# 4. Ensure logged in and navigate to Events module
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=FP_events&action=index"
sleep 4

# 5. Take initial screenshot
take_screenshot /tmp/manage_event_delegates_initial.png

echo "=== manage_event_delegates task setup complete ==="