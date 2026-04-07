#!/bin/bash
# Export script for forensic_peer_review_audit task

echo "=== Exporting results for forensic_peer_review_audit ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Kill Autopsy to release DB locks
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "forensic_peer_review_audit",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_largest_file_name": "",
    "db_largest_file_size": 0,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "error_summary_exists": False,
    "error_summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/peer_review_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Peer_Review_Audit_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Peer_Review_Audit_2024"
    with open("/tmp/peer_review_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Data source check
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_image_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass

    # Ingest completed check
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Find actual largest file in Autopsy DB for verification
    try:
        cur.execute("""
            SELECT name, size FROM tsk_files
            WHERE meta_type=1 AND size > 0
              AND name NOT IN ('.', '..', '$OrphanFiles')
              AND name NOT LIKE '$%'
              AND (dir_flags=1 OR dir_flags=2)
            ORDER BY size DESC LIMIT 1
        """)
        row = cur.fetchone()
        if row:
            result["db_largest_file_name"] = row["name"]
            result["db_largest_file_size"] = row["size"]
    except Exception as e:
        result["error"] += f" | DB largest file query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB error: {e}"

# Read Main Report
report_path = "/home/ga/Reports/peer_review_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(16384)

# Read Error Summary
summary_path = "/home/ga/Reports/error_summary.txt"
if os.path.exists(summary_path):
    result["error_summary_exists"] = True
    with open(summary_path, "r", errors="replace") as f:
        result["error_summary_content"] = f.read(8192)

with open("/tmp/peer_review_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="