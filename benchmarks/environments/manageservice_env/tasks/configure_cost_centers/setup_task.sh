#!/bin/bash
echo "=== Setting up Configure Cost Centers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running
ensure_sdp_running

# ==============================================================================
# PREPARE DATA: Ensure Departments exist and Cost Centers do NOT exist
# ==============================================================================
echo "Preparing initial database state..."

# 1. Unlink any existing cost centers from target departments to avoid FK constraint issues on delete
for dept in "Engineering" "Sales" "Marketing"; do
    sdp_db_exec "UPDATE DepartmentDefinition SET cost_center_id = NULL WHERE dept_name = '$dept';"
done

# 2. Delete target Cost Centers if they already exist (clean slate)
sdp_db_exec "DELETE FROM CostCenter WHERE cost_center_name IN ('Engineering CC', 'Sales CC', 'Marketing CC');"
sdp_db_exec "DELETE FROM AccountCostCenter WHERE cost_center_name IN ('Engineering CC', 'Sales CC', 'Marketing CC');" 2>/dev/null || true

# 3. Ensure target Departments exist
# We use a primitive check-and-insert loop via sdp_db_exec
# Note: In a real SDP instance, IDs are handled by sequences. We rely on SDP's internal logic or simplified inserts for this env.
# A safer way in this specific environment is using the API if possible, but direct DB is used here for speed/reliability in setup.

for dept in "Engineering" "Sales" "Marketing"; do
    EXISTS=$(sdp_db_exec "SELECT count(*) FROM DepartmentDefinition WHERE dept_name = '$dept';")
    if [ "$EXISTS" -eq "0" ]; then
        echo "Creating missing department: $dept"
        # Insert with dummy site_id (usually 1 or existing)
        # Assuming site_id 1 exists (Base Site)
        sdp_db_exec "INSERT INTO DepartmentDefinition (dept_id, dept_name, site_id) VALUES ((SELECT COALESCE(MAX(dept_id),0)+1 FROM DepartmentDefinition), '$dept', (SELECT site_id FROM SiteDefinition LIMIT 1));"
    fi
done

# Verify setup
echo "Verifying setup state:"
sdp_db_exec "SELECT dept_name, cost_center_id FROM DepartmentDefinition WHERE dept_name IN ('Engineering', 'Sales', 'Marketing');"

# ==============================================================================
# UI SETUP
# ==============================================================================
# Launch Firefox to the Login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Wait for window and maximize
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="