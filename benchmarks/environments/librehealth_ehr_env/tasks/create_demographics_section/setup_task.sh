#!/bin/bash
echo "=== Setting up Create Demographics Section Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 120

# Cleanup: Remove any existing RPM group or field to ensure clean state
# This prevents previous runs from interfering
echo "Cleaning up any previous RPM layout data..."
librehealth_query "DELETE FROM layout_options WHERE field_id = 'rpm_device_serial' AND form_id = 'DEM'"
# Find the group ID for 'RPM' if it exists and delete it
RPM_GRP_ID=$(librehealth_query "SELECT grp_id FROM layout_group_properties WHERE grp_title = 'RPM' AND form_id = 'DEM'" 2>/dev/null)
if [ -n "$RPM_GRP_ID" ]; then
    librehealth_query "DELETE FROM layout_group_properties WHERE grp_id = '${RPM_GRP_ID}' AND form_id = 'DEM'"
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start Firefox at the Login Page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="