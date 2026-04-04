#!/bin/bash
# Task setup: create_nutrition_plan
# Navigates the browser to the nutrition overview page.
# The agent will create a new nutrition plan named "High Protein Diet".

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_nutrition_plan task ==="

# Ensure wger is responding
wait_for_wger_page

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/nutrition/overview/" 5

# Take a starting screenshot
take_screenshot /tmp/task_create_nutrition_plan_start.png

echo "=== Task setup complete: create_nutrition_plan ==="
