#!/bin/bash
echo "=== Setting up create_trainer_rbac_group task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure wger API/web is reachable
wait_for_wger_page

# Clean state: Remove the group if it already exists to prevent false positives
echo "Ensuring clean database state..."
django_shell "from django.contrib.auth.models import Group; Group.objects.filter(name='Personal Trainers').delete()"

# Launch Firefox and navigate to the wger dashboard
# (User needs to navigate from here or use the URL bar to go to /admin/)
echo "Launching Firefox..."
launch_firefox_to "http://localhost/en/dashboard/" 5

# Ensure browser is maximized for agent visibility
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="