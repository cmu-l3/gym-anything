#!/bin/bash
# Task setup: create_workout_routine
# Navigates the browser to the workout routines overview page.
# The agent will create a new routine named "5x5 Strength Program".

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_workout_routine task ==="

# Ensure wger is responding
wait_for_wger_page

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/routine/overview" 5

# Take a starting screenshot
take_screenshot /tmp/task_create_workout_routine_start.png

echo "=== Task setup complete: create_workout_routine ==="
