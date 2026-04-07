#!/bin/bash
echo "=== Exporting configure_sales_team_access results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/configure_sales_final.png

# We use a Python script inside the container to query the Docker MariaDB
# and output a cleanly structured JSON file for the verifier on the host.
cat << 'EOF' > /tmp/export_db.py
import json
import subprocess
import os

def query_db(q):
    try:
        cmd = ["docker", "exec", "vtiger-db", "mysql", "-u", "vtiger", "-pvtiger_pass", "vtiger", "-N", "-e", q]
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except Exception:
        return ""

result = {
    "profile": None,
    "role": None,
    "user": None,
    "parent_role_id": None,
    "initial_counts": {},
    "final_counts": {}
}

# Read initial counts saved by setup_task.sh
try:
    with open('/tmp/initial_counts.json', 'r') as f:
        result["initial_counts"] = json.load(f)
except Exception:
    pass

# Current counts
result["final_counts"] = {
    "profiles": int(query_db("SELECT COUNT(*) FROM vtiger_profile") or 0),
    "roles": int(query_db("SELECT COUNT(*) FROM vtiger_role") or 0),
    "users": int(query_db("SELECT COUNT(*) FROM vtiger_users") or 0)
}

# 1. Profile Verification
p_data = query_db("SELECT profileid, profilename FROM vtiger_profile WHERE profilename='Junior Sales Access' LIMIT 1")
if p_data:
    parts = p_data.split('\t')
    if len(parts) >= 2:
        pid = parts[0]
        result["profile"] = {
            "profileid": pid, 
            "profilename": parts[1], 
            "permissions": {}
        }
        # Fetch tab permissions (0=enabled, 1=disabled in Vtiger)
        perms = query_db(f"SELECT t.name, p.permissions FROM vtiger_profile2tab p JOIN vtiger_tab t ON p.tabid = t.tabid WHERE p.profileid='{pid}'")
        for line in perms.split('\n'):
            if '\t' in line:
                tname, tperm = line.split('\t', 1)
                result["profile"]["permissions"][tname.strip()] = tperm.strip()

# 2. Role Verification
r_data = query_db("SELECT roleid, rolename, parentrole FROM vtiger_role WHERE rolename='Junior Sales Rep' LIMIT 1")
if r_data:
    parts = r_data.split('\t')
    if len(parts) >= 3:
        rid = parts[0]
        result["role"] = {
            "roleid": rid, 
            "rolename": parts[1], 
            "parentrole": parts[2], 
            "linked_profileid": None
        }
        # Fetch linked profile
        link = query_db(f"SELECT profileid FROM vtiger_role2profile WHERE roleid='{rid}' LIMIT 1")
        if link:
            result["role"]["linked_profileid"] = link.strip()

# 3. User Verification
u_data = query_db("SELECT id, user_name, first_name, last_name, email1, is_admin FROM vtiger_users WHERE user_name='sarah.mitchell' LIMIT 1")
if u_data:
    parts = u_data.split('\t')
    if len(parts) >= 6:
        uid = parts[0]
        result["user"] = {
            "id": uid, 
            "user_name": parts[1], 
            "first_name": parts[2], 
            "last_name": parts[3],
            "email1": parts[4], 
            "is_admin": parts[5], 
            "linked_roleid": None
        }
        # Fetch linked role
        link = query_db(f"SELECT roleid FROM vtiger_user2role WHERE userid='{uid}' LIMIT 1")
        if link:
            result["user"]["linked_roleid"] = link.strip()

# 4. Target Parent Role ID
parent_data = query_db("SELECT roleid FROM vtiger_role WHERE rolename='Sales Person' LIMIT 1")
if parent_data:
    result["parent_role_id"] = parent_data.strip()

with open('/tmp/configure_sales_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Execute the python script to dump the DB state
python3 /tmp/export_db.py
chmod 666 /tmp/configure_sales_result.json 2>/dev/null || true

echo "Result saved to /tmp/configure_sales_result.json"
cat /tmp/configure_sales_result.json
echo "=== configure_sales_team_access export complete ==="