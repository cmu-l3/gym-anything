#!/bin/bash
# Export script for directory_structure_profiling task

echo "=== Exporting results for directory_structure_profiling ==="

source /workspace/scripts/task_utils.sh

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "directory_structure_profiling",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "tree_file_exists": False,
    "tree_file_mtime": 0,
    "tree_file_content": "",
    "profile_file_exists": False,
    "profile_file_mtime": 0,
    "profile_file_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/directory_profile_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Directory_Profile_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found"
    with open("/tmp/directory_profile_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Read Directory Tree File
tree_path = "/home/ga/Reports/directory_tree.txt"
if os.path.exists(tree_path):
    result["tree_file_exists"] = True
    result["tree_file_mtime"] = int(os.path.getmtime(tree_path))
    # Read up to 2MB to prevent memory issues with massive trees
    with open(tree_path, "r", errors="replace") as f:
        result["tree_file_content"] = f.read(2097152)

# Read Organizational Profile
profile_path = "/home/ga/Reports/organization_profile.txt"
if os.path.exists(profile_path):
    result["profile_file_exists"] = True
    result["profile_file_mtime"] = int(os.path.getmtime(profile_path))
    with open(profile_path, "r", errors="replace") as f:
        result["profile_file_content"] = f.read(16384)

print(json.dumps(result, indent=2))
with open("/tmp/directory_profile_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/directory_profile_result.json")
PYEOF

take_screenshot /tmp/task_end.png
echo "=== Export complete ==="