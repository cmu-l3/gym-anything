#!/bin/bash
# Setup for "create_announcement" task
# Opens Firefox to ServiceDesk Plus home

echo "=== Setting up Create Announcement task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

ensure_sdp_running

ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 6

take_screenshot /tmp/create_announcement_start.png

echo "=== Create Announcement task ready ==="
echo "SDP is open in Firefox. Log in with administrator / administrator."
echo "Navigate to Admin > Announcements and create a new announcement."
