#!/bin/bash
# Export script for custodian_based_evidence_organization task

echo "=== Exporting results for custodian_based_evidence_organization ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga
sleep 1

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "custodian_based_evidence_organization",
    "case_db_found": False,
    "case_name_matches": False,
    "db_data_sources": [],
    "db_persons": [],
    "db_hosts": [],
    "manifest_file_exists": False,
    "manifest_mtime": 0,
    "manifest_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/custodian_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Custodian_Tracking_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Custodian_Tracking_2024"
    with open("/tmp/custodian_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True
print(f"Found DB: {db_path}")

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Extract Data Sources
    try:
        cur.execute("SELECT name FROM tsk_files WHERE parent_path = '/'")
        ds_rows = cur.fetchall()
        result["db_data_sources"] = [r["name"] for r in ds_rows]
    except Exception:
        try:
            cur.execute("SELECT device_id FROM data_source_info")
            ds_rows = cur.fetchall()
            result["db_data_sources"] = [r["device_id"] for r in ds_rows]
        except Exception as e:
            result["error"] += f" | DS query error: {e}"

    # Extract Persons
    try:
        cur.execute("SELECT name FROM tsk_persons")
        person_rows = cur.fetchall()
        result["db_persons"] = [r["name"] for r in person_rows]
    except Exception as e:
        result["error"] += f" | Person query error: {e}"
        # Fallback to string extraction if schema changes
        try:
            with open(db_path, 'rb') as f:
                content = f.read().decode('utf-8', errors='ignore')
                if 'Alice_Chen' in content: result["db_persons"].append('Alice_Chen')
                if 'Bob_Smith' in content: result["db_persons"].append('Bob_Smith')
        except Exception:
            pass

    # Extract Hosts
    try:
        cur.execute("SELECT name FROM tsk_hosts")
        host_rows = cur.fetchall()
        result["db_hosts"] = [r["name"] for r in host_rows]
    except Exception as e:
        result["error"] += f" | Host query error: {e}"
        try:
            with open(db_path, 'rb') as f:
                content = f.read().decode('utf-8', errors='ignore')
                if 'Alice_USB' in content: result["db_hosts"].append('Alice_USB')
                if 'Bob_Camera' in content: result["db_hosts"].append('Bob_Camera')
        except Exception:
            pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Manifest file
manifest_path = "/home/ga/Reports/custodian_manifest.csv"
if os.path.exists(manifest_path):
    result["manifest_file_exists"] = True
    result["manifest_mtime"] = int(os.path.getmtime(manifest_path))
    with open(manifest_path, "r", errors="replace") as f:
        result["manifest_content"] = f.read(4096)

# Summary file
summary_path = "/home/ga/Reports/custodian_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

print(json.dumps(result, indent=2))
with open("/tmp/custodian_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/custodian_result.json")
PYEOF

chmod 666 /tmp/custodian_result.json 2>/dev/null || true
echo "=== Export complete ==="