#!/bin/bash
# Setup for "update_request_priority" task
# Opens Firefox to the Adobe Acrobat software request

echo "=== Setting up Update Request Priority task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

# Find the Adobe Acrobat request
ADOBE_ID=$(find_request_id "Adobe")
if [ -z "$ADOBE_ID" ]; then
    ADOBE_ID=$(find_request_id "Acrobat")
fi
if [ -z "$ADOBE_ID" ]; then
    log "Adobe/Acrobat request not found, opening requests list"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
else
    log "Opening Adobe request ID: $ADOBE_ID"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do?workOrderID=${ADOBE_ID}&operation=view"
fi
sleep 6

take_screenshot /tmp/update_priority_start.png

echo "=== Update Request Priority task ready ==="
echo "SDP is open in Firefox showing the software request."
echo "Log in with administrator / administrator if needed."
echo "Change the priority of the request from Low to Medium."
