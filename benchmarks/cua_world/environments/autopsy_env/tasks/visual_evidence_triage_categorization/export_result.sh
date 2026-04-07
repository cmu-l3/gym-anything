#!/bin/bash
# Export script for visual_evidence_triage_categorization task
# Runs AFTER the agent session ends

echo "=== Exporting results for visual_evidence_triage_categorization ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json
import os
import sqlite3
import glob

result = {
    "task": "visual_evidence_triage_categorization",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "target_tag_exists": False,
    "tagged_files": [],
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/visual_triage_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Aviation_Smuggling_2024*/autopsy.db")
if not db_paths:
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db")
                if "Aviation_Smuggling_2024" in p]

if not db_paths:
    result["error"] = "autopsy.db not found for case Aviation_Smuggling_2024"
    print(json.dumps(result, indent=2))
    with open("/tmp/visual_triage_result.json", "w") as f:
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

    # Check data source was added (Logical Files usually adds to tsk_files and data_source_info)
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Check ingest completed (files indexed)
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Query tags applied to files
    try:
        # Check if Aircraft_Evidence tag exists
        cur.execute("SELECT tag_name_id FROM tag_names WHERE display_name = 'Aircraft_Evidence'")
        tag_row = cur.fetchone()
        
        if tag_row:
            result["target_tag_exists"] = True
            tag_name_id = tag_row["tag_name_id"]
            
            # Get filenames with this tag
            cur.execute("""
                SELECT tf.name
                FROM content_tags ct
                JOIN tsk_files tf ON ct.obj_id = tf.obj_id
                WHERE ct.tag_name_id = ?
            """, (tag_name_id,))
            
            tagged_rows = cur.fetchall()
            result["tagged_files"] = [r["name"] for r in tagged_rows]
            print(f"Found {len(result['tagged_files'])} files tagged with Aircraft_Evidence")
        else:
            print("Tag 'Aircraft_Evidence' not found in DB")
            
    except Exception as e:
        result["error"] += f" | Tag query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check agent's CSV report
report_path = "/home/ga/Reports/tagged_aircraft.csv"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        content = f.read(8192)
    result["report_content"] = content
    print(f"Report file exists: {len(content)} chars")

print(json.dumps(result, indent=2))
with open("/tmp/visual_triage_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/visual_triage_result.json")
PYEOF

echo "=== Export complete ==="