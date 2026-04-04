#!/bin/bash
set -e
echo "=== Setting up add_procedure_provider task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth is running and accessible
wait_for_librehealth 120

# CLEAN STATE: Remove any existing LabCorp entries to prevent false positives
# We use the docker exec method directly or the utility function
echo "Cleaning up any previous LabCorp entries..."
librehealth_query "DELETE FROM procedure_providers WHERE name LIKE '%LabCorp%' OR npi='1234567893'" 2>/dev/null || true

# Record initial count of procedure providers
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM procedure_providers" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_pp_count.txt
echo "Initial procedure provider count: $INITIAL_COUNT"

# Restart Firefox at the login page to ensure clean UI state
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="