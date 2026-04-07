#!/bin/bash
echo "=== Exporting create_gym result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use Django ORM to extract the data securely.
# getattr is used to gracefully handle schema versions where optional fields 
# (like phone/email) might not be present in the gym model.
cat > /tmp/export_gym.py << 'EOF'
import json
import os
import sys

try:
    from django.apps import apps
    from wger.gym.models import Gym
    
    gyms = Gym.objects.filter(name__icontains='FitLife Downtown').order_by('-id')
    count = Gym.objects.count()
    
    data = {
        "found": False,
        "current_count": count
    }
    
    if gyms.exists():
        g = gyms.first()
        data["found"] = True
        data["name"] = getattr(g, 'name', '')
        data["phone"] = getattr(g, 'phone', '')
        data["email"] = getattr(g, 'email', '')
        data["street"] = getattr(g, 'street', '')
        data["city"] = getattr(g, 'city', '')
        data["zip_code"] = getattr(g, 'zip_code', '')
        
    with open('/tmp/gym_export.json', 'w') as f:
        json.dump(data, f)
except Exception as e:
    with open('/tmp/gym_export.json', 'w') as f:
        json.dump({"error": str(e), "found": False, "current_count": 0}, f)
EOF

# Execute export script inside the wger-web container
docker cp /tmp/export_gym.py wger-web:/tmp/export_gym.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_gym.py').read())"
docker cp wger-web:/tmp/gym_export.json /tmp/task_result.json 2>/dev/null || true

INITIAL_COUNT=$(cat /tmp/initial_gym_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Enrich the JSON with the host-side timestamps and anti-gaming initial counts
python3 -c "
import json
import os

result_file = '/tmp/task_result.json'
if os.path.exists(result_file):
    with open(result_file, 'r') as f:
        data = json.load(f)
else:
    data = {'found': False, 'current_count': 0}

data['initial_count'] = int('$INITIAL_COUNT')
data['task_start'] = int('$TASK_START')

with open(result_file, 'w') as f:
    json.dump(data, f)
"

cat /tmp/task_result.json
echo "=== Export complete ==="