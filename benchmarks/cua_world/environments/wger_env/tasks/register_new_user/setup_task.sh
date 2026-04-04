#!/bin/bash
# Task setup: register_new_user
# Removes any pre-existing "john_trainee" user, then navigates the browser
# to the admin user creation form. The agent will register the new user.

source /workspace/scripts/task_utils.sh

echo "=== Setting up register_new_user task ==="

# Ensure wger is responding
wait_for_wger_page

# Remove any pre-existing "john_trainee" user to ensure clean state
docker exec wger-web python3 manage.py shell -c "
from django.contrib.auth.models import User
deleted, _ = User.objects.filter(username='john_trainee').delete()
print(f'Deleted {deleted} existing john_trainee user(s)')
" 2>/dev/null || echo "Warning: could not clean up existing user"

sleep 1

# Launch Firefox (handles cold start + snap permissions)
# Navigate to the gym add-member page (gym ID 1 = Default gym)
launch_firefox_to "http://localhost/en/gym/1/add-member" 5

# Take a starting screenshot
take_screenshot /tmp/task_register_new_user_start.png

echo "=== Task setup complete: register_new_user ==="
