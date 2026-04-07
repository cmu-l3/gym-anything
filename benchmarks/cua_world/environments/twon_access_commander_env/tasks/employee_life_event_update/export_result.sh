#!/bin/bash
echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run the python script to extract API state safely handling unknown endpoint structures
cat > /tmp/export_api_state.py << 'EOF'
import requests
import urllib3
import json
import os

urllib3.disable_warnings()
s = requests.Session()
s.verify = False
AC_URL = "https://localhost:9443"

try:
    s.put(f"{AC_URL}/api/v3/auth", json={"login": "admin", "password": "2n"}, timeout=10)
except Exception as e:
    pass

result = {}

def safe_get(endpoint):
    try:
        resp = s.get(f"{AC_URL}{endpoint}", timeout=5)
        if resp.status_code == 200:
            return resp.json()
    except:
        pass
    return None

result['users'] = safe_get("/api/v3/users")
result['groups'] = safe_get("/api/v3/groups")

target_user_id = None
if os.path.exists('/tmp/target_user_id.txt'):
    with open('/tmp/target_user_id.txt', 'r') as f:
        target_user_id = f.read().strip()
result['target_user_id'] = target_user_id

if target_user_id:
    result['target_user'] = safe_get(f"/api/v3/users/{target_user_id}")
    result['target_user_groups'] = safe_get(f"/api/v3/users/{target_user_id}/groups")
    result['target_user_credentials'] = safe_get(f"/api/v3/users/{target_user_id}/credentials")
    result['target_user_cards'] = safe_get(f"/api/v3/users/{target_user_id}/cards")
    result['target_user_pins'] = safe_get(f"/api/v3/users/{target_user_id}/pins")

# Get group users
if result['groups']:
    groups_data = []
    for g in result['groups']:
        gid = g.get('id')
        if gid:
            g_users = safe_get(f"/api/v3/groups/{gid}/users")
            groups_data.append({"group": g, "users": g_users})
    result['groups_data'] = groups_data

result['all_cards'] = safe_get("/api/v3/cards")
result['all_pins'] = safe_get("/api/v3/pins")

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/export_api_state.py

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "API state exported to /tmp/task_result.json"
echo "=== Export complete ==="