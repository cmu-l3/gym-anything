#!/bin/bash
echo "=== Setting up edit_gym_config task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming checks)
date +%s > /tmp/task_start_time.txt

# Ensure wger container is ready
wait_for_wger_page

# Clean up any existing matching gyms and create the initial "Downtown Fitness Hub"
# We use django_shell to bypass UI/API routing and ensure the starting state is exact
echo "Setting up initial database state..."
docker exec wger-web python3 manage.py shell -c "
try:
    from wger.gym.models import Gym
    from django.contrib.auth.models import User
    
    # Delete test targets if they exist from a previous run
    Gym.objects.filter(name__in=['Downtown Fitness Hub', 'Iron Peak Athletics']).delete()
    
    # Create the starting target gym
    Gym.objects.create(
        name='Downtown Fitness Hub'
    )
    print('Initial gym created successfully.')
except Exception as e:
    print(f'Error creating gym: {e}')
" 2>/dev/null || echo "Warning: Database setup script encountered an issue."

# Launch Firefox to the dashboard (user is already authenticated via cookies)
# launch_firefox_to handles fixing snap permissions and cold start
launch_firefox_to "http://localhost/en/dashboard/" 5

# Ensure browser is maximized for reliable agent interaction
maximize_firefox 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="