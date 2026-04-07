#!/bin/bash
echo "=== Exporting assign_gym_trainer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve end state from the database using Django ORM
cat > /tmp/wger_export_trainer.py << 'EOF'
import json
from django.contrib.auth.models import User
from wger.gym.models import Gym

try:
    try:
        gym = Gym.objects.get(name='Iron Works Fitness Center')
        gym_exists = True
        gym_id = gym.id
    except Gym.DoesNotExist:
        gym_exists = False
        gym_id = None
        
    try:
        user = User.objects.get(username='maria_coach')
        user_exists = True
        user_gym_id = user.userprofile.gym_id if hasattr(user, 'userprofile') else None
    except User.DoesNotExist:
        user_exists = False
        user_gym_id = None
        
    current_user_count = User.objects.count()
    
    print(json.dumps({
        "gym_exists": gym_exists,
        "target_gym_id": gym_id,
        "user_exists": user_exists,
        "user_gym_id": user_gym_id,
        "current_user_count": current_user_count
    }))
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

docker cp /tmp/wger_export_trainer.py wger-web:/tmp/wger_export_trainer.py
DB_STATE=$(docker exec wger-web python3 manage.py shell -c "import sys; exec(open('/tmp/wger_export_trainer.py').read())")

# Read initial state values
INITIAL_USER_COUNT=$(python3 -c "import json, sys; print(json.load(open('/tmp/initial_state.json')).get('initial_user_count', 0))" 2>/dev/null || echo "0")

# Construct final combined JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_state": $DB_STATE,
    "initial_user_count": $INITIAL_USER_COUNT,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end_time": $(date +%s),
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to standard location handling permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="