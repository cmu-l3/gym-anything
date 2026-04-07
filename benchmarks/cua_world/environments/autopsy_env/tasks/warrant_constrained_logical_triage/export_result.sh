#!/bin/bash
# Export script for warrant_constrained_logical_triage task

echo "=== Exporting results for warrant_constrained_logical_triage ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Kill Autopsy to ensure SQLite database locks are released
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "warrant_constrained_logical_triage",
    "case_db_found": False,
    "case_name_matches": False,
    "export_dir_exists": False,
    "export_dir_file_count": 0,
    "raw_image_in_export": False,
    "logical_source_added": False,
    "raw_image_added": False,
    "db_total_files": 0,
    "db_deleted_files": 0,
    "html_report_generated": False,
    "summary_file_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/warrant_constrained_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# ── 1. Check Export Directory ──────────────────────────────────────────────────
export_dir = "/home/ga/evidence/constrained_export"
if os.path.exists(export_dir) and os.path.isdir(export_dir):
    result["export_dir_exists"] = True
    
    # Recursively count files
    file_count = 0
    raw_found = False
    for root, dirs, files in os.walk(export_dir):
        file_count += len(files)
        if any(f.endswith(".dd") for f in files):
            raw_found = True
            
    result["export_dir_file_count"] = file_count
    result["raw_image_in_export"] = raw_found
    print(f"Export dir: {file_count} files found.")

# ── 2. Check Autopsy Database ──────────────────────────────────────────────────
db_paths = glob.glob("/home/ga/Cases/Constrained_Warrant_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Constrained_Warrant_2024"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    print(f"Found DB: {db_path}")

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()

        # Check if raw image was ingested (tsk_image_info is populated for raw images)
        cur.execute("SELECT COUNT(*) FROM tsk_image_info")
        image_count = cur.fetchone()[0]
        result["raw_image_added"] = image_count > 0

        # Check if logical source was added (local directories show up in tsk_files but not tsk_image_info)
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE name = 'constrained_export' OR parent_path = '/'")
        if cur.fetchone()[0] > 0 and not result["raw_image_added"]:
            result["logical_source_added"] = True

        # Check for ANY deleted files (this ensures strict warrant compliance)
        # dir_flags = 2 means TSK_FS_NAME_FLAG_UNALLOC (deleted/unallocated)
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE dir_flags = 2")
        result["db_deleted_files"] = cur.fetchone()[0]

        # Total files
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type = 1")
        result["db_total_files"] = cur.fetchone()[0]

        conn.close()
    except Exception as e:
        result["error"] += f" | DB query error: {e}"

# ── 3. Check HTML Report ───────────────────────────────────────────────────────
if result["case_db_found"]:
    case_dir = os.path.dirname(db_paths[0])
    reports_dir = os.path.join(case_dir, "Reports")
    if os.path.exists(reports_dir):
        # Look for HTML files in subdirectories
        html_reports = glob.glob(os.path.join(reports_dir, "**/*.html"), recursive=True)
        result["html_report_generated"] = len(html_reports) > 0

# ── 4. Check Summary File ──────────────────────────────────────────────────────
summary_path = "/home/ga/Reports/warrant_summary.txt"
if os.path.exists(summary_path):
    result["summary_file_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)
    print(f"Summary file loaded: {len(result['summary_content'])} chars")

print(json.dumps(result, indent=2))
with open("/tmp/warrant_constrained_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/warrant_constrained_result.json")
PYEOF

echo "=== Export complete ==="