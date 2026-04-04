#!/bin/bash
# Setup for "onboard_technician" task

echo "=== Setting up Onboard Technician task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running (this waits for install if needed)
ensure_sdp_running

# Open Firefox to the login page
# The agent needs to log in as administrator to perform these actions
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# Clean up any previous attempts (Anti-gaming / Idempotency)
# We remove the user and skill if they exist to ensure a clean start
log "Cleaning up potential stale data..."
sdp_db_exec "DELETE FROM technicianskills WHERE skillid IN (SELECT skillid FROM skill WHERE skillname = 'AWS Certified Solutions Architect');"
sdp_db_exec "DELETE FROM skill WHERE skillname = 'AWS Certified Solutions Architect';"
# Note: Deleting users in SDP via raw SQL is risky due to many FKs. 
# We rely on the specific name 'Elena Rodriguez' being unique for this task run.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Onboard Technician task ready ==="
echo "SDP is open. Log in with administrator / administrator."
echo "Follow the instructions to create the skill and technician."