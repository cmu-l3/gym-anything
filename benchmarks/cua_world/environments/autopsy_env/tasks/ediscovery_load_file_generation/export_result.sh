#!/bin/bash
# Export script for ediscovery_load_file_generation task

echo "=== Exporting results for eDiscovery Load File Generation ==="

source /workspace/scripts/task_utils.sh

# Take Final Screenshot
take_screenshot /tmp/task_final.png ga

# Kill Autopsy to release DB lock
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "ediscovery_load_file_generation",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "load_file_exists": False,
    "load_file_mtime": 0,
    "load_file_content": "",
    "export_dir_exists": False,
    "extracted_files": [],
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/ediscovery_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Litigation_Support_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "Litigation_Support_2024" in p]

if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    print(f"Found DB: {db_path}")

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass
        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"
else:
    result["error"] += "autopsy.db not found. "

# Check Load File
load_file_path = "/home/ga/Reports/eDiscovery/load_file.dat"
if os.path.exists(load_file_path):
    result["load_file_exists"] = True
    result["load_file_mtime"] = int(os.path.getmtime(load_file_path))
    with open(load_file_path, "r", errors="replace") as f:
        result["load_file_content"] = f.read(65536) # Read up to 64KB
else:
    result["error"] += "Load file not found. "

# Check Exported Natives
export_dir = "/home/ga/Reports/eDiscovery/Natives"
if os.path.exists(export_dir):
    result["export_dir_exists"] = True
    for root, dirs, files in os.walk(export_dir):
        for file in files:
            file_path = os.path.join(root, file)
            try:
                with open(file_path, "rb") as f:
                    data = f.read()
                    md5 = hashlib.md5(data).hexdigest().lower()
                    result["extracted_files"].append({
                        "filename": file,
                        "path": file_path,
                        "size": len(data),
                        "md5": md5
                    })
            except Exception:
                pass
else:
    result["error"] += "Natives directory not found. "

print(json.dumps(result, indent=2))
with open("/tmp/ediscovery_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/ediscovery_result.json")
PYEOF

echo "=== Export complete ==="