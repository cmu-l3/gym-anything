#!/bin/bash
echo "=== Setting up archive_external_email task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up any pre-existing files or database states
rm -f "/home/ga/Documents/Q4_Requirements.txt" 2>/dev/null || true

# Check if target account exists and delete
if account_exists "Global Tech Industries"; then
    echo "Cleaning up existing Account..."
    soft_delete_record "accounts" "name='Global Tech Industries'"
fi

# Clean up existing emails with the same subject
EMAIL_CHECK=$(suitecrm_db_query "SELECT COUNT(*) FROM emails WHERE name='URGENT: Q4 Procurement Requirements' AND deleted=0")
if [ "$EMAIL_CHECK" -gt 0 ]; then
    echo "Cleaning up existing Emails..."
    soft_delete_record "emails" "name='URGENT: Q4 Procurement Requirements'"
fi

# Clean up existing notes/attachments with the same filename
NOTE_CHECK=$(suitecrm_db_query "SELECT COUNT(*) FROM notes WHERE filename='Q4_Requirements.txt' AND deleted=0")
if [ "$NOTE_CHECK" -gt 0 ]; then
    echo "Cleaning up existing Notes/Attachments..."
    soft_delete_record "notes" "filename='Q4_Requirements.txt'"
fi

# 2. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# 3. Ensure logged in and navigate to Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== archive_external_email task setup complete ==="