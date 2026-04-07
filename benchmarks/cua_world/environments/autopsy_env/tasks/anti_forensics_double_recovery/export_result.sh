#!/bin/bash
echo "=== Exporting anti_forensics_double_recovery result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before altering the state
take_screenshot /tmp/task_final.png ga
sleep 1

kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, subprocess

result = {
    "task": "anti_forensics_double_recovery",
    "partition_recovered": False,
    "case_db_found": False,
    "file_system_parsed": False,
    "file_found_in_db": False,
    "file_tagged": False,
    "report_exists": False,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/task_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 1. Check partition recovery using mmls (verifies CLI tool usage)
image_path = "/home/ga/evidence/corrupted_drive.dd"
try:
    mmls_out = subprocess.check_output(["mmls", image_path], stderr=subprocess.STDOUT, text=True)
    if any(x in mmls_out.lower() for x in ["fat", "dos", "win95", "0x0b", "0x0c"]):
        result["partition_recovered"] = True
except subprocess.CalledProcessError as e:
    result["error"] += f" | mmls error: {e.output}"
except Exception as e:
    result["error"] += f" | mmls exception: {e}"

# 2. Check Autopsy DB to verify forensic ingestion
db_paths = glob.glob("/home/ga/Cases/Operation_Phoenix*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
        
        # Check if file system was successfully parsed and deleted file exists
        cur.execute("SELECT obj_id FROM tsk_files WHERE lower(name) LIKE '%secret_contact.csv%'")
        row = cur.fetchone()
        if row:
            result["file_system_parsed"] = True
            result["file_found_in_db"] = True
            obj_id = row["obj_id"]
            
            # Check if the file was tagged
            cur.execute("""
                SELECT COUNT(*) FROM content_tags 
                JOIN tag_names ON content_tags.tag_name_id = tag_names.tag_name_id
                WHERE content_tags.obj_id = ? AND lower(tag_names.display_name) LIKE '%notable%'
            """, (obj_id,))
            if cur.fetchone()[0] > 0:
                result["file_tagged"] = True
                
        conn.close()
    except Exception as e:
        result["error"] += f" | DB query error: {e}"

# 3. Check text report output
report_path = "/home/ga/Reports/recovery_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(1024)

print(json.dumps(result, indent=2))
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="