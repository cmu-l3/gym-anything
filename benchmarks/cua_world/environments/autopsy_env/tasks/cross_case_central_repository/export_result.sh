#!/bin/bash
# Export script for cross_case_central_repository task

echo "=== Exporting results for cross_case_central_repository ==="

source /workspace/scripts/task_utils.sh

# Kill Autopsy to ensure SQLite databases are flushed and unlocked
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "cross_case_central_repository",
    "cr_db_found": False,
    "cr_db_path": "",
    "cr_cases_count": 0,
    "cr_cases_names": [],
    "cr_instances_count": 0,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "shared_md5": "",
    "start_time": 0,
    "error": ""
}

# 1. Read task start time and the ground-truth MD5
try:
    with open("/tmp/cross_case_start_time") as f:
        result["start_time"] = int(f.read().strip())
    with open("/tmp/shared_md5.txt") as f:
        result["shared_md5"] = f.read().strip()
except Exception as e:
    result["error"] += f" | Setup files read error: {e}"

# 2. Locate Central Repository SQLite DB
# The agent may have saved it anywhere in /home/ga, so we scan all .db files
db_paths = glob.glob("/home/ga/**/*.db", recursive=True)
cr_db = None

for p in db_paths:
    if "autopsy.db" in p: 
        continue # Skip individual case DBs
    try:
        conn = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
        cur = conn.cursor()
        # Central Repo schema has specific tables: 'cases', 'instances', 'reference_sets'
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cases'")
        has_cases = cur.fetchone() is not None
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='instances'")
        has_instances = cur.fetchone() is not None
        conn.close()
        
        if has_cases and has_instances:
            cr_db = p
            break
    except Exception:
        pass

if cr_db:
    result["cr_db_found"] = True
    result["cr_db_path"] = cr_db
    print(f"Found Central Repository DB: {cr_db}")
    
    # Query Central Repository contents
    try:
        conn = sqlite3.connect(f"file:{cr_db}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        
        cur.execute("SELECT case_uid, case_name FROM cases")
        cases = cur.fetchall()
        result["cr_cases_count"] = len(cases)
        result["cr_cases_names"] = [c["case_name"] for c in cases]
        
        cur.execute("SELECT COUNT(*) FROM instances")
        result["cr_instances_count"] = cur.fetchone()[0]
        
        conn.close()
    except Exception as e:
        result["error"] += f" | CR DB query error: {e}"
else:
    print("Central Repository DB not found.")

# 3. Read the agent's report file
report_path = "/home/ga/Reports/cross_case_intelligence.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(4096)
    print(f"Report file found: {len(result['report_content'])} chars")
else:
    print("Report file not found.")

# Export to JSON
print(json.dumps(result, indent=2))
with open("/tmp/cross_case_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/cross_case_result.json")
PYEOF

echo "=== Export complete ==="