#!/bin/bash
# Export script for disk_partition_triage task

echo "=== Exporting results for disk_partition_triage ==="

source /workspace/scripts/task_utils.sh

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
kill_autopsy
sleep 3

# Take final screenshot (though UI is dead, keeping for consistency)
take_screenshot /tmp/task_final_state.png ga 2>/dev/null || true

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "disk_partition_triage",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/disk_triage_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Disk_Triage_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Disk_Triage_2024"
    with open("/tmp/disk_triage_result.json", "w") as f:
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

    # Check data source
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Check ingest (any files indexed)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check agent's triage report
report_path = "/home/ga/Reports/disk_triage_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(16384)
    print(f"Report file: {len(result['report_content'])} chars")

# Check agent's narrative summary
summary_path = "/home/ga/Reports/triage_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(8192)
    print(f"Summary file: {len(result['summary_content'])} chars")

print(json.dumps(result, indent=2))
with open("/tmp/disk_triage_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/disk_triage_result.json")
PYEOF

echo "=== Export complete ==="