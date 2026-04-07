#!/bin/bash
# Export script for email_archive_forensic_analysis task

echo "=== Exporting results for email_archive_forensic_analysis ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "email_archive_forensic_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "logical_file_added": False,
    "email_parser_executed": False,
    "db_email_artifact_count": 0,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/email_task_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Email_Investigation_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Email_Investigation_2024"
    with open("/tmp/email_task_result.json", "w") as f:
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

    # Check if Logical File was added (usually shows up in tsk_files with the exact name)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE name='communications.mbox'")
        count = cur.fetchone()[0]
        result["logical_file_added"] = count > 0
    except Exception as e:
        result["error"] += f" | Logical file query error: {e}"

    # Check for TSK_EMAIL_MSG artifacts
    try:
        cur.execute("""
            SELECT COUNT(*) 
            FROM blackboard_artifacts ba
            JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
            WHERE bat.type_name = 'TSK_EMAIL_MSG'
        """)
        email_count = cur.fetchone()[0]
        result["db_email_artifact_count"] = email_count
        result["email_parser_executed"] = email_count > 0
    except Exception as e:
        result["error"] += f" | Email artifact query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check agent's report file
report_path = "/home/ga/Reports/email_forensics_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        content = f.read(8192)
    result["report_content"] = content
    print(f"Report file: {len(content)} chars")
else:
    print("Report file not found")

print(json.dumps(result, indent=2))
with open("/tmp/email_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/email_task_result.json")
PYEOF

echo "=== Export complete ==="