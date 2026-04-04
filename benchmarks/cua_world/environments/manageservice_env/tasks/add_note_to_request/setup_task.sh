#!/bin/bash
# Setup for "add_note_to_request" task
# Opens Firefox to the email/SMTP request

echo "=== Setting up Add Note to Request task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

# Find the email/SMTP request
EMAIL_ID=$(find_request_id "Email account")
if [ -z "$EMAIL_ID" ]; then
    EMAIL_ID=$(find_request_id "SMTP")
fi
if [ -z "$EMAIL_ID" ]; then
    log "Email request not found, opening requests list"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do"
else
    log "Opening email request ID: $EMAIL_ID"
    ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/WorkOrder.do?workOrderID=${EMAIL_ID}&operation=view"
fi
sleep 6

take_screenshot /tmp/add_note_start.png

echo "=== Add Note task ready ==="
echo "SDP is open in Firefox. Log in with administrator / administrator if needed."
echo "Add an internal note to the email request."
