#!/bin/bash
echo "=== Setting up Create Custom Visit Form Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 120

# CLEANUP: Remove any existing form with the target ID or Title to ensure a fresh start
# This prevents the agent from getting credit for a pre-existing form (anti-gaming)
echo "Cleaning up any existing 'LBF_Neuro' forms..."
librehealth_query "DELETE FROM layout_options WHERE form_id = 'LBF_Neuro'" 2>/dev/null || true
librehealth_query "DELETE FROM layout_options WHERE title = 'Neurology Intake'" 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# Start Firefox at the login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Create 'Neurology Intake' form (ID: LBF_Neuro)"
echo "Login: admin / password"