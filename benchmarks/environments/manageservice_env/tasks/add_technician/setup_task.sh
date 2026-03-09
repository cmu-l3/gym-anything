#!/bin/bash
# Setup for "add_technician" task
# Opens Firefox to ServiceDesk Plus Admin section

echo "=== Setting up Add Technician task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 6

take_screenshot /tmp/add_technician_start.png

echo "=== Add Technician task ready ==="
echo "SDP is open in Firefox. Log in with administrator / administrator."
echo "Navigate to Admin > Technicians & Roles and add a new technician."
