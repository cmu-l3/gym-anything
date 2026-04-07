#!/bin/bash
# Export script for forensic_report_generation task

echo "=== Exporting results for forensic_report_generation ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before killing the app
take_screenshot /tmp/forensic_final.png

# Kill Autopsy to release SQLite lock on the database
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# Gather results via Python script
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "forensic_report_generation",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "html_reports": [],
    "memo_exists": False,
    "memo_mtime": 0,
    "memo_content": "",
    "start_time": 0,
    "error": ""
}

# 1. Read start time
try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 2. Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/DA_Report_Case_2024*/autopsy.db")
if not db_paths:
    # Try broader search
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "DA_Report_Case_2024" in p]

if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    
    case_dir = os.path.dirname(db_path)
    print(f"Found DB: {db_path} in {case_dir}")
    
    # Analyze Autopsy SQLite Database
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        # Check data source was added
        try:
            cur.execute("SELECT name FROM data_source_info")
            sources = cur.fetchall()
            if sources:
                result["data_source_added"] = any("ntfs_undel" in r["name"].lower() for r in sources)
        except Exception:
            try:
                cur.execute("SELECT name FROM tsk_image_info")
                sources = cur.fetchall()
                if sources:
                    result["data_source_added"] = any("ntfs_undel" in r["name"].lower() for r in sources)
            except Exception:
                pass

        # Check ingest completed (files indexed)
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass

        conn.close()
    except Exception as e:
        result["error"] += f" | DB open error: {e}"
        
    # 3. Locate Autopsy HTML Report
    reports_dir = os.path.join(case_dir, "Reports")
    if os.path.exists(reports_dir):
        # Find index.html or Report.html files
        html_files = []
        for root, dirs, files in os.walk(reports_dir):
            for file in files:
                if file.lower().endswith('.html'):
                    path = os.path.join(root, file)
                    mtime = int(os.path.getmtime(path))
                    size = os.path.getsize(path)
                    
                    # Grab a sample of content to prove it's a real report
                    sample = ""
                    try:
                        with open(path, "r", errors="replace") as f:
                            sample = f.read(2048)
                    except Exception:
                        pass
                        
                    html_files.append({
                        "path": path,
                        "dir": root,
                        "mtime": mtime,
                        "size": size,
                        "content_sample": sample
                    })
        result["html_reports"] = html_files

# 4. Check agent's memo file
memo_path = "/home/ga/Reports/case_summary_memo.txt"
if os.path.exists(memo_path):
    result["memo_exists"] = True
    result["memo_mtime"] = int(os.path.getmtime(memo_path))
    with open(memo_path, "r", errors="replace") as f:
        content = f.read(8192)
    result["memo_content"] = content
    print(f"Memo file found: {len(content)} chars")
else:
    print("Memo file not found")

# Write to tmp
with open("/tmp/forensic_report_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/forensic_report_result.json")
PYEOF

echo "=== Export complete ==="