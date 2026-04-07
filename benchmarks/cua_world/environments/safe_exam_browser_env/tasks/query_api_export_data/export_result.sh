#!/bin/bash
set -e

echo "=== Exporting query_api_export_data results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

# Run Python script to securely parse JSONs, verify timestamps, and query database
python3 << 'PYEOF'
import json
import os
import subprocess

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=30
        )
        return result.stdout.strip()
    except Exception:
        return "0"

# Read start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    start_time = 0.0

export_dir = "/home/ga/api_export"
files = {
    "institutions": os.path.join(export_dir, "institutions.json"),
    "users": os.path.join(export_dir, "users.json"),
    "configurations": os.path.join(export_dir, "configurations.json")
}

result = {
    "task_start_time": start_time,
    "dir_exists": os.path.isdir(export_dir),
    "files_exist": {},
    "files_valid_json": {},
    "files_created_after_start": {},
    "data_counts": {},
    "db_counts": {
        "institutions": int(db_query("SELECT COUNT(*) FROM institution") or 0),
        "users": int(db_query("SELECT COUNT(*) FROM user") or 0),
        "configurations": int(db_query("SELECT COUNT(*) FROM configuration_node") or 0)
    }
}

for key, path in files.items():
    exists = os.path.isfile(path)
    result["files_exist"][key] = exists
    result["files_valid_json"][key] = False
    result["files_created_after_start"][key] = False
    result["data_counts"][key] = 0
    
    if exists:
        mtime = os.path.getmtime(path)
        result["files_created_after_start"][key] = mtime > start_time
        try:
            with open(path, 'r') as f:
                data = json.load(f)
            result["files_valid_json"][key] = True
            
            # API can return a list or a dictionary with paginated content
            if isinstance(data, list):
                result["data_counts"][key] = len(data)
            elif isinstance(data, dict):
                # Handle standard Spring Data REST wrapper
                if "content" in data and isinstance(data["content"], list):
                    result["data_counts"][key] = len(data["content"])
                else:
                    # Fallback to counting top-level keys
                    result["data_counts"][key] = len(data)
        except Exception as e:
            pass

# Write result securely
temp_path = '/tmp/temp_task_result.json'
with open(temp_path, 'w') as f:
    json.dump(result, f, indent=2)

subprocess.run(['cp', temp_path, '/tmp/task_result.json'])
subprocess.run(['chmod', '666', '/tmp/task_result.json'])
subprocess.run(['rm', '-f', temp_path])

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="