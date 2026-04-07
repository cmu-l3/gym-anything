#!/bin/bash
echo "=== Exporting disguised_document_authorship_triage result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Kill Autopsy to ensure the SQLite DB is flushed and lock is released
kill_autopsy
sleep 3

# 3. Extract SQLite database states and the report using Python
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "disguised_document_authorship_triage",
    "case_db_found": False,
    "data_source_added": False,
    "file_type_id_ran": False,
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Check Autopsy SQLite database for anti-gaming verification
db_paths = glob.glob("/home/ga/Cases/Authorship_Triage_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check if Logical Files were added
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            pass
            
        # Check if File Type Identification successfully assigned MIME types
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE mime_type IS NOT NULL AND mime_type != '' AND mime_type != 'application/octet-stream'")
            result["file_type_id_ran"] = cur.fetchone()[0] > 0
        except Exception:
            pass

        conn.close()
    except Exception as e:
        result["error"] += f"DB read error: {e}"

# Read Agent's Report
report_path = "/home/ga/Reports/authorship_attribution.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(8192)

with open("/tmp/authorship_triage_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON written to /tmp/authorship_triage_result.json"
echo "=== Export complete ==="