#!/bin/bash
echo "=== Setting up create_faq_entries task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any existing FAQs that might overlap to ensure a clean state
echo "Cleaning up overlapping FAQs..."
vtiger_db_query "UPDATE vtiger_crmentity SET deleted=1 WHERE setype='Faq' AND crmid IN (SELECT id FROM vtiger_faq WHERE question LIKE '%cancellation policy%' OR question LIKE '%passport validity%' OR question LIKE '%baggage allowance%')"

# 2. Record initial state for anti-gaming verification
INITIAL_FAQ_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_faq f JOIN vtiger_crmentity c ON f.id=c.crmid WHERE c.deleted=0" | tr -d '[:space:]')
INITIAL_MAX_ID=$(vtiger_db_query "SELECT COALESCE(MAX(id), 0) FROM vtiger_faq" | tr -d '[:space:]')

echo "Initial FAQ count: $INITIAL_FAQ_COUNT"
echo "Initial Max ID: $INITIAL_MAX_ID"

rm -f /tmp/initial_faq_count.txt /tmp/initial_max_id.txt 2>/dev/null || true
echo "$INITIAL_FAQ_COUNT" > /tmp/initial_faq_count.txt
echo "$INITIAL_MAX_ID" > /tmp/initial_max_id.txt
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/initial_faq_count.txt /tmp/initial_max_id.txt /tmp/task_start_time.txt 2>/dev/null || true

# 3. Ensure logged in and navigate to the FAQ list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Faq&view=List"
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/create_faq_initial.png

echo "=== create_faq_entries task setup complete ==="
echo "Task: Create three FAQ entries for travel support"
echo "Agent should click Add Faq and fill in the forms consecutively"