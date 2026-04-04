#!/bin/bash
echo "=== Setting up Configure Self-Service Portal Task ==="

# Source utilities to handle SDP startup
source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running (waits for install if needed)
ensure_sdp_running

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Reset/Ensure Initial State via Database
# We want to ensure the state isn't ALREADY correct, so the agent actually has to do work.
# - Enable Reopen (so agent has to disable it)
# - Disable Show Cost (so agent has to enable it)
# - Set generic Welcome Message
echo "Resetting portal settings to default..."

# Note: Table and param names are best-guess based on SDP schema patterns. 
# If exact params aren't found, the task relies on UI state, but we try DB injection for robustness.
sdp_db_exec "UPDATE GlobalConfig SET paramvalue='true' WHERE parameter='REOPEN_RESOLVED_REQUEST';"
sdp_db_exec "UPDATE GlobalConfig SET paramvalue='false' WHERE parameter='SHOW_REQ_COST';"
# Reset welcome message might be complex if it's in a different table, but we'll try a common location
sdp_db_exec "UPDATE GlobalConfig SET paramvalue='Welcome to ServiceDesk Plus' WHERE parameter='WELCOME_MESSAGE';"

# 4. Record Initial DB State for comparison
echo "Recording initial database state..."
# Dump relevant GlobalConfig rows to a temp file
sdp_db_exec "SELECT parameter, paramvalue FROM GlobalConfig WHERE parameter IN ('REOPEN_RESOLVED_REQUEST', 'SHOW_REQ_COST', 'WELCOME_MESSAGE');" > /tmp/initial_db_state.txt
cat /tmp/initial_db_state.txt

# 5. Launch Firefox to the Login Page
# The agent needs to log in, so we start at the login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 6. Capture Initial Screenshot
sleep 5
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="