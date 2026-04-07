#!/bin/bash
echo "=== Exporting restrict_analytics_db_user result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Run a Python script to deeply test the database access and export JSON
# This simulates the BI application trying to connect and do various actions
cat << 'EOF' > /tmp/test_db_access.py
import subprocess
import json
import os
import time

result = {
    "user_exists": False,
    "auth_success": False,
    "read_success": False,
    "write_denied": False,
    "create_denied": False,
    "grants": []
}

try:
    # 1. Check if user still exists
    user_check = subprocess.run(
        ["mysql", "-u", "root", "-N", "-e", "SELECT User FROM mysql.user WHERE User='analytics_user' AND Host='localhost';"],
        capture_output=True, text=True, timeout=5
    )
    if "analytics_user" in user_check.stdout:
        result["user_exists"] = True

    # 2. Check Authentication & Read (using the requested new password)
    read_cmd = ["mysql", "-u", "analytics_user", "-pDataViz#2026", "-N", "-e", "SELECT COUNT(*) FROM socioboard.user_details;"]
    read_check = subprocess.run(read_cmd, capture_output=True, text=True, timeout=5)

    if read_check.returncode == 0 and read_check.stdout.strip().isdigit():
        result["auth_success"] = True
        result["read_success"] = True

    # 3. Check Write Denial (Insert attempt)
    write_cmd = ["mysql", "-u", "analytics_user", "-pDataViz#2026", "-e", "INSERT INTO socioboard.user_details (email, first_name) VALUES ('hack@test.com', 'hack');"]
    write_check = subprocess.run(write_cmd, capture_output=True, text=True, timeout=5)

    if write_check.returncode != 0:
        result["write_denied"] = True
    else:
        # If the hack write actually succeeded, clean it up
        subprocess.run(["mysql", "-u", "root", "-e", "DELETE FROM socioboard.user_details WHERE email='hack@test.com';"])

    # 4. Check Schema Modification Denial (Create Table attempt)
    create_cmd = ["mysql", "-u", "analytics_user", "-pDataViz#2026", "-e", "CREATE TABLE socioboard.security_test (id INT);"]
    create_check = subprocess.run(create_cmd, capture_output=True, text=True, timeout=5)

    if create_check.returncode != 0:
        result["create_denied"] = True
    else:
        # If the schema hack succeeded, clean it up
        subprocess.run(["mysql", "-u", "root", "-e", "DROP TABLE IF EXISTS socioboard.security_test;"])

    # 5. Fetch effective Grants directly from database
    grants_cmd = ["mysql", "-u", "root", "-N", "-e", "SHOW GRANTS FOR 'analytics_user'@'localhost';"]
    grants_check = subprocess.run(grants_cmd, capture_output=True, text=True, timeout=5)
    
    if grants_check.returncode == 0:
        result["grants"] = [line.strip() for line in grants_check.stdout.strip().split('\n') if line.strip()]

except Exception as e:
    result["error"] = str(e)

# Write JSON safely to a temporary file
with open("/tmp/restrict_user_result.tmp.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/test_db_access.py

# Move with permission handling to ensure verifier.py can read it via copy_from_env
rm -f /tmp/restrict_user_result.json 2>/dev/null || sudo rm -f /tmp/restrict_user_result.json 2>/dev/null || true
cp /tmp/restrict_user_result.tmp.json /tmp/restrict_user_result.json 2>/dev/null || sudo cp /tmp/restrict_user_result.tmp.json /tmp/restrict_user_result.json
chmod 666 /tmp/restrict_user_result.json 2>/dev/null || sudo chmod 666 /tmp/restrict_user_result.json 2>/dev/null || true
rm -f /tmp/restrict_user_result.tmp.json

echo "Result JSON successfully extracted and saved to /tmp/restrict_user_result.json"
cat /tmp/restrict_user_result.json
echo "=== Export complete ==="