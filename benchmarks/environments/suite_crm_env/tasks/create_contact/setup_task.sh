#!/bin/bash
echo "=== Setting up create_contact task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record initial contact count
INITIAL_CONTACT_COUNT=$(get_contact_count)
echo "Initial contact count: $INITIAL_CONTACT_COUNT"
rm -f /tmp/initial_contact_count.txt 2>/dev/null || true
echo "$INITIAL_CONTACT_COUNT" > /tmp/initial_contact_count.txt
chmod 666 /tmp/initial_contact_count.txt 2>/dev/null || true

# 2. Verify the target contact does not already exist
if contact_exists "Marcus" "Whitfield"; then
    echo "WARNING: Contact Marcus Whitfield already exists, removing"
    soft_delete_record "contacts" "first_name='Marcus' AND last_name='Whitfield'"
fi

# 3. Ensure logged in and navigate to Contacts list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Contacts&action=index"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/create_contact_initial.png

echo "=== create_contact task setup complete ==="
echo "Task: Create a new contact Marcus Whitfield at Boeing Company"
echo "Agent should click Create Contact and fill in the form"
