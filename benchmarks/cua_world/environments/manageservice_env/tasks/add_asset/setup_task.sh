#!/bin/bash
# Setup for "add_asset" task
# Opens Firefox to ServiceDesk Plus Asset Management

echo "=== Setting up Add Asset task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 6

take_screenshot /tmp/add_asset_start.png

echo "=== Add Asset task ready ==="
echo "SDP is open in Firefox. Log in with administrator / administrator."
echo "Navigate to Assets > IT Assets and add a new workstation asset."
