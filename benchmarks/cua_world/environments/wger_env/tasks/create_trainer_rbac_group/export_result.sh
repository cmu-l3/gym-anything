#!/bin/bash
echo "=== Exporting create_trainer_rbac_group task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the group using Django ORM
# We write a python script to a file and execute it inside the container
# writing the output to a JSON file to avoid stdout pollution/warnings
cat > /tmp/check_group.py << 'EOF'
import json
from django.contrib.auth.models import Group

try:
    group = Group.objects.get(name='Personal Trainers')
    # Extract codenames (e.g., 'add_exercise', 'change_exercise')
    perms = list(group.permissions.values_list('codename', flat=True))
    result = {
        'group_exists': True,
        'permissions': perms,
        'permission_count': len(perms)
    }
except Group.DoesNotExist:
    result = {
        'group_exists': False,
        'permissions': [],
        'permission_count': 0
    }
except Exception as e:
    result = {
        'group_exists': False,
        'permissions': [],
        'permission_count': 0,
        'error': str(e)
    }

with open('/tmp/group_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Execute script inside container
docker cp /tmp/check_group.py wger-web:/tmp/check_group.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/check_group.py').read())"

# Retrieve the result JSON
docker cp wger-web:/tmp/group_result.json /tmp/task_result_temp.json 2>/dev/null || echo '{"group_exists": false, "permissions": [], "permission_count": 0}' > /tmp/task_result_temp.json

# Merge with timestamp metadata
python3 -c "
import json
import os

try:
    with open('/tmp/task_result_temp.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {'group_exists': False, 'permissions': [], 'permission_count': 0}

data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['screenshot_path'] = '/tmp/task_final.png'

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions so the host verifier can read it
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="