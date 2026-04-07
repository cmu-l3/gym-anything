#!/bin/bash
echo "=== Setting up create_gym task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for wger web service to be reachable
wait_for_wger_page

# Ensure clean state: delete any existing gyms matching the target name
docker exec wger-web python3 manage.py shell -c "
from wger.gym.models import Gym
deleted = Gym.objects.filter(name__icontains='FitLife Downtown').delete()
print(f'Cleaned up pre-existing target gyms: {deleted}')
" 2>/dev/null || true

# Record initial gym count for anti-gaming verification
INITIAL_GYM_COUNT=$(docker exec wger-web python3 manage.py shell -c "from wger.gym.models import Gym; print(Gym.objects.count())" 2>/dev/null | tail -1 || echo "0")
echo "$INITIAL_GYM_COUNT" > /tmp/initial_gym_count.txt

# Launch Firefox and navigate to dashboard (admin session should be active via setup profile)
launch_firefox_to "http://localhost/en/dashboard" 5

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Initial gym count saved: $INITIAL_GYM_COUNT"