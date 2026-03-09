#!/bin/bash
# Setup for "create_problem" task
# Opens Firefox to ServiceDesk Plus Problems module

echo "=== Setting up Create Problem task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 6

take_screenshot /tmp/create_problem_start.png

echo "=== Create Problem task ready ==="
echo "SDP is open in Firefox. Log in with administrator / administrator."
echo "Navigate to Problems and create a new problem record."
