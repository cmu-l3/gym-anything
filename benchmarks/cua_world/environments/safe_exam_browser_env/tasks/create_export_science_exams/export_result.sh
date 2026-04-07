#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting create_export_science_exams results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run an embedded Python script to extract structured info from the MariaDB and File System
python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    start_time = 0.0

configs = ["Math_Final_Offline", "Physics_Final_Offline", "Bio_Final_Offline"]
urls = {
    "Math_Final_Offline": "https://math.edu/exam",
    "Physics_Final_Offline": "https://physics.edu/exam",
    "Bio_Final_Offline": "https://bio.edu/exam"
}

results = {
    "task_start_time": start_time,
    "timestamp": time.time(),
    "configs": {},
    "files": {},
    "firefox_running": False
}

# 1. Check DB for Configurations
for c in configs:
    # Check config exists
    c_count = db_query(f"SELECT COUNT(*) FROM configuration_node WHERE name='{c}' AND type='EXAM_CONFIG'")
    c_exists = int(c_count) > 0 if (c_count and c_count.isdigit()) else False
    
    # Check URL setting
    url = urls[c]
    # In SEB Server, settings are stored in seb_setting table. We search for the URL in string values.
    u_count = db_query(f"SELECT COUNT(*) FROM seb_setting WHERE value LIKE '%{url}%'")
    u_exists = int(u_count) > 0 if (u_count and u_count.isdigit()) else False
    
    results["configs"][c] = {
        "exists": c_exists,
        "url_correct": u_exists
    }

# 2. Check File System for exported .seb files
backup_dir = "/home/ga/Documents/ExamBackups"
backup_dir_exists = os.path.exists(backup_dir) and os.path.isdir(backup_dir)
results["backup_dir_exists"] = backup_dir_exists

for c in configs:
    expected_file = os.path.join(backup_dir, f"{c}.seb")
    f_exists = os.path.exists(expected_file)
    f_size = os.path.getsize(expected_file) if f_exists else 0
    f_mtime = os.path.getmtime(expected_file) if f_exists else 0
    f_recent = f_mtime > start_time if f_exists else False
    
    results["files"][c] = {
        "exists": f_exists,
        "size_bytes": f_size,
        "recent": f_recent
    }

# 3. Process Check
try:
    proc = subprocess.run(['pgrep', '-f', 'firefox'], capture_output=True)
    results["firefox_running"] = (proc.returncode == 0)
except Exception:
    pass

# Write out JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print(json.dumps(results, indent=2))
PYEOF

echo "=== Export complete ==="