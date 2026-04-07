#!/bin/bash
# Setup script for configure_system_holidays
# Ensures OpenProject is running, logs in as admin, and prepares the browser.

source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_system_holidays task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for OpenProject availability
wait_for_openproject

# 3. Launch Firefox to the login page
launch_firefox_to "http://localhost:8080/login" 5

# 4. Automate Login as Admin
# We do this so the agent starts in an actionable state (logged in)
# The task description says "Log in as admin", but starting logged in
# reduces friction for this specific configuration task.
# If the agent needs to log in manually, we can skip this, but 
# consistent with other tasks, we often pre-login or provide credentials.
# Given the description says "Log in as admin", we will let the agent do it
# OR we can do it for them. Let's do it for them to focus on the configuration task.
# We will update the browser to the home page if login succeeds.

echo "Performing automated login..."
focus_window "Mozilla Firefox"
sleep 1

# Type username
xdotool type "admin"
xdotool key Tab
sleep 0.5

# Type password
xdotool type "Admin1234!"
xdotool key Return
sleep 5

# Navigate to home to ensure clean state
navigate_to "http://localhost:8080/" 3

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

# 6. Record initial DB state (count of non-working days in 2026)
# This helps us detect if they were already there (unlikely, but good practice)
op_rails "puts NonWorkingDay.where('date >= ? AND date <= ?', '2026-01-01', '2026-12-31').count" > /tmp/initial_holiday_count.txt 2>/dev/null || echo "0" > /tmp/initial_holiday_count.txt

echo "=== Task setup complete ==="