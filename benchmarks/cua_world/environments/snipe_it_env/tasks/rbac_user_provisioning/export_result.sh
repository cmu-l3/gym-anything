#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting RBAC User Provisioning results ==="

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Create a robust Python script to extract DB/API state to JSON
cat > /tmp/export_state.py << 'EOF'
import json
import subprocess
import urllib.request
import os

def db_query(query):
    cmd = f"docker exec snipeit-db mysql -u snipeit -psnipeit_pass snipeit -N -e \"{query}\""
    try:
        return subprocess.check_output(cmd, shell=True).decode('utf-8').strip()
    except Exception as e:
        return ""

def api_get(endpoint):
    try:
        with open("/home/ga/snipeit/api_token.txt", "r") as f:
            token = f.read().strip()
    except:
        return {}

    req = urllib.request.Request(f"http://localhost:8000/api/v1/{endpoint}")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        return {"error": str(e)}

result = {}

# 1. Read initial state
try:
    with open("/tmp/initial_user_count.txt", "r") as f:
        result["initial_user_count"] = int(f.read().strip())
    with open("/tmp/initial_group_count.txt", "r") as f:
        result["initial_group_count"] = int(f.read().strip())
except:
    result["initial_user_count"] = 0
    result["initial_group_count"] = 0

# 2. Get current counts
result["final_user_count"] = int(db_query("SELECT COUNT(*) FROM users WHERE deleted_at IS NULL") or 0)
result["final_group_count"] = int(db_query("SELECT COUNT(*) FROM permission_groups") or 0)

# 3. Get Groups and their JSON permissions from DB
groups_raw = db_query("SELECT id, name, permissions FROM permission_groups")
groups = []
for line in groups_raw.split('\n'):
    if not line.strip():
        continue
    parts = line.split('\t')
    if len(parts) >= 2:
        g_id = parts[0]
        g_name = parts[1]
        perms = {}
        if len(parts) >= 3 and parts[2].strip() and parts[2].strip() != "NULL":
            try:
                perms = json.loads(parts[2].strip())
            except:
                pass
        groups.append({
            "id": g_id,
            "name": g_name,
            "permissions": perms
        })
result["groups"] = groups

# 4. Get target users and their group assignments via API
users = {}
for uname in ["msantos", "jchen", "ppatel"]:
    api_data = api_get(f"users?search={uname}")
    found = False
    if "rows" in api_data:
        for row in api_data["rows"]:
            if row.get("username") == uname:
                groups_list = []
                # Snipe-IT API embeds group membership
                if "groups" in row and isinstance(row["groups"], dict) and "rows" in row["groups"]:
                    groups_list = [g.get("name") for g in row["groups"]["rows"]]
                
                users[uname] = {
                    "username": row.get("username"),
                    "email": row.get("email"),
                    "first_name": row.get("first_name"),
                    "last_name": row.get("last_name"),
                    "employee_num": row.get("employee_num"),
                    "jobtitle": row.get("jobtitle"),
                    "groups": groups_list
                }
                found = True
                break
    if not found:
        users[uname] = None

result["users"] = users

# Save result JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Execute the python script
python3 /tmp/export_state.py

# Ensure permissions are correct
chmod 666 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== RBAC User Provisioning export complete ==="