#!/bin/bash
echo "=== Setting up delete_workout_routine task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for wger to be fully available
wait_for_wger_page

# -----------------------------------------------------------------------
# Ensure exact starting state (clean routines, create the 3 needed)
# -----------------------------------------------------------------------
echo "=== Configuring routines in database ==="
django_shell "
import datetime
from django.contrib.auth.models import User
from wger.manager.models import Routine

admin = User.objects.get(username='admin')

# Clear existing routines to ensure pristine state
Routine.objects.filter(user=admin).delete()

today = datetime.date.today()
end = today + datetime.timedelta(days=180)

routines_needed = [
    ('Push-Pull-Legs', 'Classic PPL split for hypertrophy and strength'),
    ('5x5 Beginner', 'Foundational strength program with compound lifts'),
    ('Upper-Lower Split', 'Alternating upper and lower body training'),
]

for name, desc in routines_needed:
    Routine.objects.create(
        name=name, user=admin,
        description=desc, start=today, end=end
    )
print('Database setup complete. Configured 3 routines.')
"

# -----------------------------------------------------------------------
# Record initial state
# -----------------------------------------------------------------------
INITIAL_ROUTINE_COUNT=$(django_shell "
from wger.manager.models import Routine
from django.contrib.auth.models import User
print(Routine.objects.filter(user=User.objects.get(username='admin')).count())
" | tr -d '[:space:]')

echo "$INITIAL_ROUTINE_COUNT" > /tmp/initial_routine_count.txt
echo "Initial routine count: $INITIAL_ROUTINE_COUNT"

# -----------------------------------------------------------------------
# Launch Firefox
# -----------------------------------------------------------------------
echo "Launching Firefox to wger homepage..."
launch_firefox_to "http://localhost/en/user/login" 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="