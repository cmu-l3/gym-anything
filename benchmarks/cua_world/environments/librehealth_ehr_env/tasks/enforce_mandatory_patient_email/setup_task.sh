#!/bin/bash
echo "=== Setting up Enforce Mandatory Patient Email Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# --- PREPARE DATA STATE ---
# We must ensure the field starts as 'Optional' (1) so the agent has work to do.
# If it's already 2, the task is trivial/pre-completed.
# Table: layout_options, Field: email, Form: DEM

echo "Resetting Email field configuration to Optional..."
librehealth_query "UPDATE layout_options SET uor = 1 WHERE field_id = 'email' AND form_id = 'DEM'"

# Verify the reset worked and record initial state
INITIAL_UOR=$(librehealth_query "SELECT uor FROM layout_options WHERE field_id = 'email' AND form_id = 'DEM'" 2>/dev/null || echo "-1")
echo "$INITIAL_UOR" > /tmp/initial_uor.txt

echo "Initial UOR state recorded: $INITIAL_UOR (Expected: 1)"

# --- PREPARE UI STATE ---
# Start Firefox at the login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="