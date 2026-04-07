#!/bin/bash
echo "=== Setting up Create User Role Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Delete the role if it already exists
# We use the REST API for this if possible, or DB query
echo "Ensuring role 'Safety Auditor' does not exist..."

# Try deleting via REST (Role resource)
# Note: Role names with spaces need URL encoding
omrs_delete "/role/Safety%20Auditor" 2>/dev/null || true

# Double check via Database to be absolutely sure
omrs_db_query "DELETE FROM role_privilege WHERE role = 'Safety Auditor';" 2>/dev/null || true
omrs_db_query "DELETE FROM role_role WHERE parent_role = 'Safety Auditor' OR child_role = 'Safety Auditor';" 2>/dev/null || true
omrs_db_query "DELETE FROM role WHERE role = 'Safety Auditor';" 2>/dev/null || true

# Open Firefox and log in
# We start at the Home page; the agent must navigate to Admin
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# Maximize Firefox for best visibility
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Create role 'Safety Auditor' with privileges 'View Patients' and 'View Encounters'."