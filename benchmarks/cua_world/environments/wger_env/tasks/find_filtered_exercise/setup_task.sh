#!/bin/bash
echo "=== Setting up find_filtered_exercise task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# Wait for wger web service
wait_for_wger_page

# Ensure baseline "Push-Pull-Legs" routine exists and delete any existing "Pull Day"
# This guarantees a clean initial state.
cat > /tmp/wger_setup.py << 'EOF'
import datetime
from wger.manager.models import Routine, Day
from django.contrib.auth.models import User

try:
    admin = User.objects.filter(username='admin').first()
    if admin:
        routine, created = Routine.objects.get_or_create(
            name='Push-Pull-Legs',
            user=admin,
            defaults={'description': 'Classic PPL split', 'start': datetime.date.today()}
        )
        # Clear out any pre-existing "Pull Day"
        Day.objects.filter(routine=routine, name__iexact='Pull Day').delete()
        print(f"Setup complete. Routine exists: True, Clean state: True")
except Exception as e:
    print(f"Error during setup: {e}")
EOF

docker cp /tmp/wger_setup.py wger-web:/tmp/wger_setup.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_setup.py').read())"

# Launch Firefox to login page
launch_firefox_to "http://localhost/en/user/login" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="