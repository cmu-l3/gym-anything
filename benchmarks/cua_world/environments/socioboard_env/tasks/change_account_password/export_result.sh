#!/bin/bash
echo "=== Exporting change_account_password result ==="

source /workspace/scripts/task_utils.sh

# Take final state screenshot
take_screenshot /tmp/task_final.png

# Run Python script to evaluate DB state and test API authentication securely
python3 << 'EOF'
import json
import os
import subprocess
import tempfile

ADMIN_EMAIL = "admin@socioboard.local"
OLD_PASS = "Admin2024!"
NEW_PASS = "SecureBoard#2025!"

def test_login(email, password):
    """Attempt login via Socioboard's user microservice API."""
    body = {"user": email, "password": password}
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(body, f)
        tmp_name = f.name
    try:
        res = subprocess.run(
            ['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
             '-d', '@'+tmp_name, 'http://127.0.0.1:3000/v1/login'],
            capture_output=True, text=True, timeout=15
        )
        data = json.loads(res.stdout)
        # If accessToken exists, login was successful
        return "accessToken" in data
    except Exception as e:
        print(f"Error testing login for {email}: {e}")
        return False
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)

# 1. Fetch current hash and updated timestamp from Database
db_cmd = f"mysql -u root socioboard -N -B -e \"SELECT password, UNIX_TIMESTAMP(updated_at) FROM user_details WHERE email='{ADMIN_EMAIL}' LIMIT 1\""
try:
    db_res = subprocess.run(db_cmd, shell=True, capture_output=True, text=True).stdout.strip().split('\t')
    current_hash = db_res[0] if len(db_res) > 0 else ""
    updated_at = float(db_res[1]) if len(db_res) > 1 and db_res[1] else 0.0
except Exception:
    current_hash = ""
    updated_at = 0.0

# 2. Fetch initial task state
try:
    with open('/tmp/initial_pwd_hash.txt', 'r') as f:
        initial_hash = f.read().strip()
except Exception:
    initial_hash = ""

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    start_time = 0.0

# 3. Test Authentication physically (Anti-Gaming)
old_login_works = test_login(ADMIN_EMAIL, OLD_PASS)
new_login_works = test_login(ADMIN_EMAIL, NEW_PASS)

# 4. Check Agent Confirmation File
file_exists = os.path.exists('/tmp/password_change_done.txt')

result = {
    "initial_hash": initial_hash,
    "current_hash": current_hash,
    "hash_changed": (initial_hash != current_hash) and bool(current_hash),
    "updated_after_start": updated_at >= start_time,
    "old_login_works": old_login_works,
    "new_login_works": new_login_works,
    "confirmation_file_exists": file_exists
}

# 5. Export JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Task Result Exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="