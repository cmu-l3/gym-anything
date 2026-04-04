#!/bin/bash
# Setup for "create_request" task
# Opens Firefox to ServiceDesk Plus login page

echo "=== Setting up Create Request task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 6

take_screenshot /tmp/create_request_start.png

echo "=== Create Request task ready ==="
echo "SDP is open in Firefox. Log in with administrator / administrator"
echo "Create a new service request with the details in the task description."
