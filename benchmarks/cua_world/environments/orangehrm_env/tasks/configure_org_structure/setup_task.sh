#!/bin/bash
set -e
echo "=== Setting up configure_org_structure task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure OrangeHRM is accessible
wait_for_http "$ORANGEHRM_URL" 120

# 1. Clean existing subunits to ensure a clean state
# We keep the root node (id=1) but delete everything else
echo "Cleaning existing organizational structure..."
orangehrm_db_query "DELETE FROM ohrm_subunit WHERE id > 1;" 2>/dev/null || true

# 2. Reset the root node's nested set pointers
# Root should be lft=1, rgt=2, level=0 when it has no children
echo "Resetting root node..."
orangehrm_db_query "UPDATE ohrm_subunit SET lft=1, rgt=2, level=0 WHERE id=1;" 2>/dev/null || true

# Record initial subunit count (should be 0 non-root units)
INITIAL_COUNT=$(orangehrm_count "ohrm_subunit" "id > 1")
echo "$INITIAL_COUNT" > /tmp/initial_subunit_count.txt
echo "Initial non-root subunits: $INITIAL_COUNT"

# 3. Navigate to the Organization Structure page
ORG_STRUCTURE_URL="${ORANGEHRM_URL}/web/index.php/admin/viewCompanyStructure"
ensure_orangehrm_logged_in "$ORG_STRUCTURE_URL"

# Wait for page to load and ensure browser is focused
sleep 5
focus_firefox
maximize_active_window

# 4. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="