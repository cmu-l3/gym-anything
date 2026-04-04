#!/bin/bash
set -e
echo "=== Setting up add_document_category task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is running and accessible
wait_for_librehealth 120

# Clean State: Remove the category if it already exists from a previous run
# This ensures the agent must actually create it to pass
EXISTING=$(librehealth_query "SELECT COUNT(*) FROM categories WHERE name='Telehealth Consent'" 2>/dev/null || echo "0")
if [ "$EXISTING" -gt "0" ]; then
    echo "Removing pre-existing 'Telehealth Consent' category..."
    librehealth_query "DELETE FROM categories WHERE name='Telehealth Consent'"
fi

# Record initial category count
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM categories" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial category count: $INITIAL_COUNT"

# Ensure the root 'Categories' node exists (ID 1 usually)
ROOT_CHECK=$(librehealth_query "SELECT id FROM categories WHERE name='Categories'" 2>/dev/null || echo "")
if [ -z "$ROOT_CHECK" ]; then
    echo "WARNING: Root 'Categories' node not found. System might be in unusual state."
fi

# Restart Firefox at the login page to give a clean start
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="