#!/bin/bash
echo "=== Exporting privileged_access_audit_remediation results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# We use an embedded Python script to safely parse MariaDB outputs into structured JSON.
# This avoids raw bash string manipulation vulnerabilities and handles JSON escaping safely.
cat > /tmp/export_db_state.py << 'EOF'
import json
import subprocess
import os

def db_query(q):
    cmd = f'docker exec snipeit-db mysql -u snipeit -psnipeit_pass snipeit -N -e "{q}"'
    try:
        out = subprocess.check_output(cmd, shell=True, text=True)
        return [line.split('\t') for line in out.strip().split('\n') if line]
    except Exception as e:
        return []

result = {
    "users": {},
    "asset": {},
    "report": []
}

# 1. Get Group & Status IDs
grp_rows = db_query("SELECT id FROM permission_groups WHERE name='Department Managers'")
grp_id = grp_rows[0][0] if grp_rows else "0"

rtd_rows = db_query("SELECT id FROM status_labels WHERE name='Ready to Deploy'")
rtd_id = rtd_rows[0][0] if rtd_rows else "0"

# 2. Extract state for all relevant users
user_names = "'admin', 'jdoe', 'asmith', 'bjones', 'cwilliams', 'evance'"
users_data = db_query(f"SELECT id, username, activated, permissions, deleted_at FROM users WHERE username IN ({user_names})")

for u in users_data:
    if len(u) < 5: continue
    uid, uname, act, perms, del_at = u[0], u[1], u[2], u[3], u[4]
    
    # Check group assignment
    in_grp = False
    if grp_id != "0":
        g_check = db_query(f"SELECT 1 FROM users_groups WHERE user_id={uid} AND group_id={grp_id}")
        in_grp = len(g_check) > 0

    # Parse permissions carefully (Snipe-IT stores as {"superuser":"1"} or {"superuser":1})
    is_su = False
    if perms and perms != 'NULL':
        try:
            p_dict = json.loads(perms)
            if str(p_dict.get("superuser", "0")) == "1":
                is_su = True
        except:
            if '"superuser":"1"' in perms or '"superuser":1' in perms:
                is_su = True

    result["users"][uname] = {
        "id": uid,
        "activated": str(act) == "1",
        "is_superuser": is_su,
        "is_deleted": del_at != "NULL" and del_at != "",
        "in_mgr_group": in_grp
    }

# 3. Extract asset state
ast_data = db_query("SELECT status_id, assigned_to FROM assets WHERE asset_tag='ASSET-EXT-01' AND deleted_at IS NULL")
if ast_data:
    stat_id, ass_to = ast_data[0][0], ast_data[0][1]
    result["asset"] = {
        "found": True,
        "is_ready": stat_id == rtd_id,
        "is_checked_in": ass_to == "NULL" or ass_to == "" or ass_to == "0"
    }
else:
    result["asset"] = {"found": False}

# 4. Extract report file contents
report_path = "/home/ga/Desktop/access_remediation_report.txt"
if os.path.exists(report_path):
    try:
        with open(report_path, "r") as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
            result["report"] = lines
    except:
        pass

# Write safely to output
with open("/tmp/privileged_access_audit_remediation_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Run python script securely
python3 /tmp/export_db_state.py

# Ensure permissions
chmod 666 /tmp/privileged_access_audit_remediation_result.json 2>/dev/null || true

echo "Result JSON Exported:"
cat /tmp/privileged_access_audit_remediation_result.json
echo "=== Export Complete ==="