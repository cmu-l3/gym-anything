#!/bin/bash
# Task setup: change_weight_unit
# Ensures the admin user's weight unit is set to kg (default) and navigates
# to the user profile page. The agent will change it to lb.

source /workspace/scripts/task_utils.sh

echo "=== Setting up change_weight_unit task (navigating to user preferences page) ==="

# Ensure wger is responding
wait_for_wger_page

# Reset weight unit to kg (default) for clean task state
docker exec wger-web python3 manage.py shell -c "
from wger.core.models import UserProfile
from django.contrib.auth.models import User
u = User.objects.get(username='admin')
profile = UserProfile.objects.get(user=u)
profile.weight_unit = 'kg'
profile.save()
print('Reset weight unit to kg')
" 2>/dev/null || echo "Warning: could not reset weight unit"

sleep 1

# Launch Firefox (handles cold start + snap permissions)
# User preferences URL: /en/user/preferences (has Weight unit dropdown)
launch_firefox_to "http://localhost/en/user/preferences" 5

# Take a starting screenshot
take_screenshot /tmp/task_change_weight_unit_start.png

echo "=== Task setup complete: change_weight_unit ==="
