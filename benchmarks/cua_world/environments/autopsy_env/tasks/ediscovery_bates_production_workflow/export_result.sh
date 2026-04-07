#!/bin/bash
# Export script for ediscovery_bates_production_workflow task

echo "=== Exporting results for E-Discovery Bates Production ==="

source /workspace/scripts/task_utils.sh

# Record final state visual evidence
take_screenshot /tmp/task_final.png

# Kill Autopsy to release SQLite locks
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "ediscovery_bates_production_workflow",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "bates_files": {},
    "raw_files": [],
    "load_file_exists": False,
    "load_file_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/ediscovery_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Check Autopsy Case DB
db_paths = glob.glob("/home/ga/Cases/EDiscovery_Smith_v_Corp*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    print(f"Found DB: {db_path}")
    result["case_db_found"] = True
    result["case_name_matches"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        if cur.fetchone()[0] > 0:
            result["data_source_added"] = True
        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"
else:
    result["error"] += " | autopsy.db not found for case EDiscovery_Smith_v_Corp"

# Process bates directory
bates_dir = "/home/ga/Reports/Production/bates"
if os.path.isdir(bates_dir):
    for fn in os.listdir(bates_dir):
        path = os.path.join(bates_dir, fn)
        if os.path.isfile(path) and fn.lower().endswith('.txt'):
            with open(path, 'rb') as f:
                content = f.read()
                result["bates_files"][fn] = {
                    "md5": hashlib.md5(content).hexdigest(),
                    "size": len(content)
                }

# Record raw exported files
raw_dir = "/home/ga/Reports/Production/raw"
if os.path.isdir(raw_dir):
    result["raw_files"] = [f for f in os.listdir(raw_dir) if os.path.isfile(os.path.join(raw_dir, f))]

# Read load file
load_file = "/home/ga/Reports/Production/load_file.csv"
if os.path.isfile(load_file):
    result["load_file_exists"] = True
    with open(load_file, "r", errors="replace") as f:
        result["load_file_content"] = f.read(100000)

print(json.dumps(result, indent=2))
with open("/tmp/ediscovery_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/ediscovery_result.json")
PYEOF

echo "=== Export complete ==="