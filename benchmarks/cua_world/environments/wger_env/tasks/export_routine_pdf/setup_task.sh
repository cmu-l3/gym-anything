#!/bin/bash
echo "=== Setting up export_routine_pdf task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# 2. Prepare the Downloads directory (clean state)
mkdir -p /home/ga/Downloads/
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true
chown -R ga:ga /home/ga/Downloads/

# 3. Ensure the initial database state is strictly correct
# (Delete any existing renamed versions, ensure exactly one "Push-Pull-Legs" exists)
echo "Resetting routine state in database..."
django_shell "
from wger.manager.models import Routine
from django.contrib.auth.models import User
try:
    admin = User.objects.get(username='admin')
    # Clean up any previously renamed routines
    Routine.objects.filter(name='Push-Pull-Legs (Hypertrophy Phase)', user=admin).delete()
    
    # Ensure the target routine exists
    routine, created = Routine.objects.get_or_create(name='Push-Pull-Legs', user=admin)
    routine.description = 'Classic PPL split for hypertrophy and strength'
    routine.save()
    print('Routine state reset successfully.')
except Exception as e:
    print(f'Error setting up DB: {e}')
"

# 4. Wait for web application to be ready
wait_for_wger_page

# 5. Launch Firefox to the routine overview page
launch_firefox_to "http://localhost/en/routine/overview" 5

# 6. Take initial evidence screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="