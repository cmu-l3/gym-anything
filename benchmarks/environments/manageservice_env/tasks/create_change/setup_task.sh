#!/bin/bash
# Setup for "create_change" task
# Opens Firefox to ServiceDesk Plus Change Management

echo "=== Setting up Create Change task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 6

take_screenshot /tmp/create_change_start.png

echo "=== Create Change task ready ==="
echo "SDP is open in Firefox. Log in with administrator / administrator."
echo "Navigate to Change Management and create a new normal change request."
