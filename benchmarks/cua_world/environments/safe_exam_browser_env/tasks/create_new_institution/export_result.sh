#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting create_new_institution results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

# Run Python script to securely query DB and dump JSON result
python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=15
        )
        return result.stdout.strip()
    except Exception as e:
        print(f"DB Query failed: {e}")
        return ""

# Load initial state
initial_state = {"initial_count": 0, "task_start_time": 0}
try:
    with open('/tmp/initial_state.json', 'r') as f:
        initial_state = json.load(f)
except Exception as e:
    print(f"Warning: Could not load initial state: {e}")

# Look for the target institution
target_name = "Pacific Northwest Health Sciences Testing Center"
exists_count = db_query(f"SELECT COUNT(*) FROM institution WHERE name='{target_name}'")
exists = int(exists_count) if exists_count and exists_count.isdigit() else 0

inst_data = {}
if exists > 0:
    inst_id = db_query(f"SELECT id FROM institution WHERE name='{target_name}' ORDER BY id DESC LIMIT 1")
    if inst_id:
        name = db_query(f"SELECT name FROM institution WHERE id={inst_id}")
        url_suffix = db_query(f"SELECT url_suffix FROM institution WHERE id={inst_id}")
        active = db_query(f"SELECT active FROM institution WHERE id={inst_id}")
        
        inst_data = {
            "id": inst_id,
            "name": name,
            "url_suffix": url_suffix if url_suffix != 'NULL' else "",
            "active": str(active).strip() in ('1', 'true', 'True')
        }

# Get current total count for anti-gaming checks
current_count_str = db_query("SELECT COUNT(*) FROM institution")
current_count = int(current_count_str) if current_count_str and current_count_str.isdigit() else 0

# Check if browser was kept running
firefox_running = 1 if subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True).returncode == 0 else 0

result = {
    "timestamp": time.time(),
    "initial_count": initial_state.get("initial_count", 0),
    "current_count": current_count,
    "target_exists": exists > 0,
    "institution": inst_data,
    "newly_created": current_count > initial_state.get("initial_count", 0),
    "firefox_running": firefox_running
}

# Write output safely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Result JSON generated:")
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="