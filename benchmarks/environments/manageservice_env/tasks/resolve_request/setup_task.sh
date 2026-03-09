#!/bin/bash
# Setup for "resolve_request" task
# Opens Firefox to the printer paper-jam request

echo "=== Setting up Resolve Request task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

# Find the printer request
PRINTER_ID=$(find_request_id "printer")
if [ -z "$PRINTER_ID" ]; then
    log "Printer request not found, opening requests list"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
else
    log "Opening printer request ID: $PRINTER_ID"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do?workOrderID=${PRINTER_ID}&operation=view"
fi
sleep 6

take_screenshot /tmp/resolve_request_start.png

echo "=== Resolve Request task ready ==="
echo "SDP is open in Firefox showing the printer request."
echo "Log in with administrator / administrator if needed."
echo "Resolve the request with a resolution note."
