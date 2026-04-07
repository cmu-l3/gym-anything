#!/bin/bash
# Export script for custom_magic_signature_identification task

echo "=== Exporting results for custom_magic_signature_identification ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
kill_autopsy
sleep 3

# ── Gather results via Python script ──────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "custom_magic_signature_identification",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_custom_mime_files": [],
    "db_total_files_indexed": 0,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/c2_hunting_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/C2_Hunting_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "C2_Hunting_2024" in p]

if not db_paths:
    result["error"] = "autopsy.db not found for case C2_Hunting_2024"
    with open("/tmp/c2_hunting_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
print(f"Found DB: {db_path}")
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Check data source was added
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Check ingest completed (files indexed)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["db_total_files_indexed"] = cur.fetchone()[0]
        result["ingest_completed"] = result["db_total_files_indexed"] > 0
    except Exception:
        pass

    # CRITICAL: Check if custom MIME type was successfully configured and detected files
    try:
        cur.execute("""
            SELECT name, mime_type
            FROM tsk_files
            WHERE mime_type = 'application/x-xyz-config'
              AND meta_type=1
        """)
        rows = cur.fetchall()
        result["db_custom_mime_files"] = [r["name"] for r in rows]
    except Exception as e:
        result["error"] += f" | DB query error for MIME type: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check agent's CSV report
report_path = "/home/ga/Reports/c2_discovered_configs.csv"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(8192)
    print(f"Report file: {len(result['report_content'])} chars")
else:
    print("CSV Report file not found")

print(json.dumps(result, indent=2))
with open("/tmp/c2_hunting_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/c2_hunting_result.json")
PYEOF

echo "=== Export complete ==="