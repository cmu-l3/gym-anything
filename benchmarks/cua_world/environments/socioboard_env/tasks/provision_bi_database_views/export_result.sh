#!/bin/bash
echo "=== Exporting Secure BI Database Provisioning result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use Python to interact with MariaDB and serialize the state cleanly to JSON
python3 << 'EOF'
import json
import subprocess
import os

result = {
    "error": None,
    "view_user_cols": [],
    "view_social_cols": [],
    "user_exists": False,
    "can_read_user_view": False,
    "can_read_social_view": False,
    "can_read_user_base": False,
    "can_read_social_base": False,
    "artifact_exists": False,
    "artifact_size": 0,
    "artifact_created_during_task": False,
    "terminal_used": True
}

def run_query(query, db="socioboard", user="root", pwd=""):
    cmd = f"mysql -u {user} "
    if pwd:
        cmd += f"-p'{pwd}' "
    cmd += f"{db} -N -e \"{query}\""
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode().strip()
    except subprocess.CalledProcessError:
        return None

# 1. Check Views and Columns
out_user = run_query("SHOW COLUMNS FROM bi_user_export")
if out_user:
    result["view_user_cols"] = [line.split('\t')[0].lower() for line in out_user.split('\n') if line]

out_social = run_query("SHOW COLUMNS FROM bi_social_export")
if out_social:
    result["view_social_cols"] = [line.split('\t')[0].lower() for line in out_social.split('\n') if line]

# 2. Check User Existence
out_user_exists = run_query("SELECT User FROM mysql.user WHERE User='bi_viewer'", db="mysql")
if out_user_exists and 'bi_viewer' in out_user_exists:
    result["user_exists"] = True

# 3. Check Privileges & Access
# Can read views?
if result["user_exists"]:
    test_view1 = run_query("SELECT 1 FROM bi_user_export LIMIT 1", user="bi_viewer", pwd="SecureBI#2025")
    result["can_read_user_view"] = test_view1 is not None
    
    test_view2 = run_query("SELECT 1 FROM bi_social_export LIMIT 1", user="bi_viewer", pwd="SecureBI#2025")
    result["can_read_social_view"] = test_view2 is not None

    # Base table blocks? (Should be blocked, so run_query returning None means success/denied)
    test_base1 = run_query("SELECT 1 FROM user_details LIMIT 1", user="bi_viewer", pwd="SecureBI#2025")
    result["can_read_user_base"] = test_base1 is not None

    # Try to dynamically find the social account base table to check if it's blocked
    tables_out = run_query("SHOW TABLES")
    if tables_out:
        tables = [t for t in tables_out.split('\n') if t]
        social_table = next((t for t in tables if 'social' in t and 'account' in t and 'export' not in t), None)
        if social_table:
            test_base2 = run_query(f"SELECT 1 FROM {social_table} LIMIT 1", user="bi_viewer", pwd="SecureBI#2025")
            result["can_read_social_base"] = test_base2 is not None

# 4. Check Artifact
artifact_path = '/home/ga/bi_initial_extract.csv'
if os.path.exists(artifact_path):
    result["artifact_exists"] = True
    result["artifact_size"] = os.path.getsize(artifact_path)
    artifact_mtime = os.path.getmtime(artifact_path)
    
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            start_time = float(f.read().strip())
        result["artifact_created_during_task"] = artifact_mtime >= start_time
    except Exception:
        result["artifact_created_during_task"] = True

# Write to file
try:
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f"Error writing JSON: {e}")

EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="