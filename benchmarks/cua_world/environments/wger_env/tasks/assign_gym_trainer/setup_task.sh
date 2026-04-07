#!/bin/bash
echo "=== Setting up assign_gym_trainer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be ready
wait_for_wger_page

# Create the gym and the user via Django ORM inside the container
echo "Creating gym and user in database..."
cat > /tmp/wger_setup_trainer.py << 'EOF'
import sys
import json
from django.contrib.auth.models import User
from wger.gym.models import Gym

try:
    # 1. Create the gym
    gym, gym_created = Gym.objects.get_or_create(
        name='Iron Works Fitness Center',
        defaults={
            'zip_code': '10001',
            'city': 'New York',
            'street': '450 W 33rd Street'
        }
    )
    
    # 2. Create the trainer user
    user, user_created = User.objects.get_or_create(
        username='maria_coach',
        defaults={
            'first_name': 'Maria',
            'last_name': 'Santos',
            'email': 'maria.santos@ironworksfitness.com'
        }
    )
    if user_created:
        user.set_password('trainer2024!')
        user.save()
        
    # 3. Ensure userprofile exists and gym is NOT set (Initial State)
    profile = user.userprofile
    profile.gym = None
    profile.save()
    
    # 4. Get total user count
    user_count = User.objects.count()
    
    print(json.dumps({
        "status": "success",
        "gym_id": gym.id,
        "user_id": user.id,
        "initial_user_count": user_count
    }))
except Exception as e:
    print(json.dumps({"status": "error", "message": str(e)}))
EOF

# Execute the setup script inside the container
docker cp /tmp/wger_setup_trainer.py wger-web:/tmp/wger_setup_trainer.py
SETUP_RESULT=$(docker exec wger-web python3 manage.py shell -c "import sys; exec(open('/tmp/wger_setup_trainer.py').read())")

echo "Setup Result: $SETUP_RESULT"
echo "$SETUP_RESULT" > /tmp/initial_state.json

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/gym/list" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="