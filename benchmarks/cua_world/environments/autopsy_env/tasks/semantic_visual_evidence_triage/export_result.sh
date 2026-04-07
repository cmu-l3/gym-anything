#!/bin/bash
echo "=== Exporting results for semantic_visual_evidence_triage ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot to capture UI state at exit
take_screenshot /tmp/task_final.png

# Kill Autopsy to ensure the internal SQLite DB isn't locked
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "semantic_visual_evidence_triage",
    "case_db_found": False,
    "logical_files_added": False,
    "report_exists": False,
    "report_content": "",
    "error": ""
}

# 1. Locate autopsy.db for the newly created case
db_paths = glob.glob("/home/ga/Cases/Visual_Triage_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # 2. Check if the logical files directory was properly ingested
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE name LIKE '%.jpg'")
        count = cur.fetchone()[0]
        if count > 0:
            result["logical_files_added"] = True
            
        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# 3. Read agent's output report
report_path = "/home/ga/Reports/visual_targets.csv"
if os.path.exists(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read()

# 4. Serialize to JSON for verification script to process
with open("/tmp/visual_triage_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="