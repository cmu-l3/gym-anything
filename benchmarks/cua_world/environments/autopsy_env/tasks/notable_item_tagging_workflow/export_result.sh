#!/bin/bash
# Export script for notable_item_tagging_workflow task

echo "=== Exporting results for notable_item_tagging_workflow ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before killing the app
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to release SQLite locks
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "notable_item_tagging_workflow",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_notable_tags_count": 0,
    "db_followup_tags_count": 0,
    "db_tagged_deleted_files": [],
    "db_tagged_allocated_files": [],
    "db_tag_comments": [],
    "html_report_generated": False,
    "html_report_path": "",
    "html_report_mtime": 0,
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/tagging_workflow_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Court_Prep_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Court_Prep_2024"
    with open("/tmp/tagging_workflow_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
case_dir = os.path.dirname(db_path)
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

    # Check ingest
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["ingest_completed"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Extract tags
    try:
        cur.execute("""
            SELECT 
                t.name AS filename, 
                t.dir_flags,
                tn.display_name AS tag_name, 
                ct.comment
            FROM content_tags ct
            JOIN tag_names tn ON ct.tag_name_id = tn.tag_name_id
            JOIN tsk_files t ON ct.obj_id = t.obj_id
        """)
        rows = cur.fetchall()
        
        for r in rows:
            tag = r["tag_name"]
            filename = r["filename"]
            flags = r["dir_flags"]  # 1 = allocated, 2 = unallocated/deleted
            comment = r["comment"] or ""
            
            if tag == "Notable Item":
                result["db_notable_tags_count"] += 1
                result["db_tagged_deleted_files"].append(filename)
            elif tag == "Follow Up":
                result["db_followup_tags_count"] += 1
                result["db_tagged_allocated_files"].append(filename)
                
            if comment:
                result["db_tag_comments"].append(comment)
                
    except Exception as e:
        result["error"] += f" | Tag query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check for HTML Report
try:
    # Autopsy places reports in CaseDir/Reports/ReportName/
    report_glob = os.path.join(case_dir, "Reports", "**", "index.html")
    html_reports = glob.glob(report_glob, recursive=True)
    
    if html_reports:
        result["html_report_generated"] = True
        result["html_report_path"] = html_reports[0]
        result["html_report_mtime"] = int(os.path.getmtime(html_reports[0]))
        print(f"Found HTML report: {html_reports[0]}")
except Exception as e:
    result["error"] += f" | Report check error: {e}"

# Check agent's summary file
summary_path = "/home/ga/Reports/tagging_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)
    print(f"Summary file found: {len(result['summary_content'])} chars")

print(json.dumps(result, indent=2))
with open("/tmp/tagging_workflow_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/tagging_workflow_result.json")
PYEOF

echo "=== Export complete ==="