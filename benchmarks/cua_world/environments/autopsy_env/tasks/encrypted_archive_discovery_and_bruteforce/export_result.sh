#!/bin/bash
# Export script for encrypted_archive_discovery_and_bruteforce task

echo "=== Exporting results ==="
source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to ensure SQLite DB writes are flushed
echo "Terminating Autopsy to release DB locks..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "encrypted_archive_discovery_and_bruteforce",
    "case_db_found": False,
    "tagged_files": [],
    "tag_applied": False,
    "exported_zip_exists": False,
    "exported_zip_name": "",
    "uncovered_files": [],
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/task_start_time", "r") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 1. Autopsy DB verification
db_paths = glob.glob("/home/ga/Cases/Encrypted_Triage_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        
        # Look for the ENCRYPTED_CONTRABAND tag
        cur.execute("""
            SELECT tsk_files.name as filename
            FROM content_tags
            JOIN tsk_files ON content_tags.obj_id = tsk_files.obj_id
            JOIN tag_names ON content_tags.tag_name_id = tag_names.tag_name_id
            WHERE tag_names.display_name = 'ENCRYPTED_CONTRABAND'
        """)
        rows = cur.fetchall()
        for r in rows:
            result["tagged_files"].append(r["filename"])
            result["tag_applied"] = True
            
        conn.close()
    except Exception as e:
        result["error"] += f"DB Query Error: {str(e)} "
else:
    result["error"] += "Case DB not found. "

# 2. Check exported archives directory
export_dir = "/home/ga/Reports/exported_archives"
if os.path.exists(export_dir):
    files = os.listdir(export_dir)
    zip_files = [f for f in files if f.endswith('.zip')]
    if zip_files:
        result["exported_zip_exists"] = True
        result["exported_zip_name"] = zip_files[0]

# 3. Check uncovered evidence directory
uncovered_dir = "/home/ga/Reports/uncovered_evidence"
if os.path.exists(uncovered_dir):
    result["uncovered_files"] = os.listdir(uncovered_dir)

# 4. Check report file
report_path = "/home/ga/Reports/decryption_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    try:
        with open(report_path, "r", encoding="utf-8", errors="replace") as f:
            result["report_content"] = f.read(4096)
    except Exception as e:
        result["error"] += f"Report Read Error: {str(e)} "

# Save result JSON safely
with open("/tmp/encrypted_archive_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported Result: {json.dumps(result, indent=2)}")
PYEOF

chmod 666 /tmp/encrypted_archive_result.json 2>/dev/null || true
echo "=== Export complete ==="