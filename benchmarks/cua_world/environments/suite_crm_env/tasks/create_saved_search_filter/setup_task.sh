#!/bin/bash
echo "=== Setting up create_saved_search_filter task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming (to verify search is created DURING task)
date +%s > /tmp/task_start_time.txt

# Delete any existing search with the same name to prevent false positives
echo "Cleaning up any existing target searches..."
suitecrm_db_query "UPDATE saved_search SET deleted=1 WHERE name='Texas Tech Customers'"

# Record initial count of saved searches
INITIAL_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM saved_search WHERE deleted=0" | tr -d '[:space:]')
echo "$INITIAL_COUNT" > /tmp/initial_search_count.txt
echo "Initial saved search count: $INITIAL_COUNT"

# Ensure logged in and navigate to Accounts list view
echo "Ensuring user is logged in and on the Accounts list view..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Accounts&action=index"
sleep 5

# Take initial screenshot to prove starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="