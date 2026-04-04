#!/bin/bash
# Setup for "assign_technician" task
# Opens Firefox to the VPN request

echo "=== Setting up Assign Technician task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

# Find the VPN request by subject
VPN_ID=$(find_request_id "VPN")
if [ -z "$VPN_ID" ]; then
    log "VPN request not found, opening requests list"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
else
    log "Opening VPN request ID: $VPN_ID"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do?workOrderID=${VPN_ID}&operation=view"
fi
sleep 6

take_screenshot /tmp/assign_technician_start.png

echo "=== Assign Technician task ready ==="
echo "SDP is open in Firefox showing the VPN request."
echo "Log in with administrator / administrator if needed."
echo "Assign the request to technician: administrator"
