#!/bin/bash
echo "=== Exporting rotate_db_credentials result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Check connection with new password
if mysql -u socioboard -p"SecureS0cial2026#" socioboard -e "SELECT 1;" >/dev/null 2>&1; then
    export NEW_PASS_SUCCESS="True"
else
    export NEW_PASS_SUCCESS="False"
fi

# Check connection with old password
if mysql -u socioboard -p"SocioPass2024!" socioboard -e "SELECT 1;" >/dev/null 2>&1; then
    export OLD_PASS_SUCCESS="True"
else
    export OLD_PASS_SUCCESS="False"
fi

# Run a python script to count file occurrences and dump a structured JSON
# Avoiding shell escaping issues by using os.environ mapping
python3 << 'PYEOF'
import os
import json
import subprocess

new_pass_success = os.environ.get('NEW_PASS_SUCCESS') == 'True'
old_pass_success = os.environ.get('OLD_PASS_SUCCESS') == 'True'

def count_occurrences(word):
    try:
        # Exclude directories where the agent shouldn't be looking to optimize execution
        cmd = ['grep', '-rl', '--exclude-dir=node_modules', '--exclude-dir=vendor', '--exclude-dir=.git', word, '/opt/socioboard/']
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            lines = [l for l in result.stdout.split('\n') if l.strip()]
            return len(lines), lines
        return 0, []
    except Exception:
        return 0, []

new_count, new_files = count_occurrences("SecureS0cial2026#")
old_count, old_files = count_occurrences("SocioPass2024!")

pm2_status = []
try:
    pm2_res = subprocess.run(['pm2', 'jlist'], capture_output=True, text=True)
    if pm2_res.returncode == 0:
        pm2_status = json.loads(pm2_res.stdout)
except Exception:
    pass

result = {
    "new_pass_success": new_pass_success,
    "old_pass_success": old_pass_success,
    "new_pass_files_count": new_count,
    "new_pass_files": new_files,
    "old_pass_files_count": old_count,
    "old_pass_files": old_files,
    "pm2_status": pm2_status
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="