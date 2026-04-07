#!/bin/bash
# Export script for allocation_delta_correlation_analysis task

echo "=== Exporting results for allocation_delta_correlation_analysis ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, subprocess

result = {
    "task": "allocation_delta_correlation_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "is_unmounted": True,
    "mounted_report_exists": False,
    "mounted_report_mtime": 0,
    "mounted_report_lines": 0,
    "delta_report_exists": False,
    "delta_report_mtime": 0,
    "delta_report_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/delta_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Check if image is currently unmounted (hygiene check)
try:
    mount_output = subprocess.check_output("mount", shell=True).decode()
    if "/home/ga/mnt/usb_ro" in mount_output:
        result["is_unmounted"] = False
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Delta_Analysis_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check data source was added
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            try:
                cur.execute("SELECT COUNT(*) FROM tsk_image_info")
                result["data_source_added"] = cur.fetchone()[0] > 0
            except Exception:
                pass
        conn.close()
    except Exception as e:
        result["error"] += f" | DB open error: {e}"

# Check mounted_txt_files.txt
mounted_report = "/home/ga/Reports/mounted_txt_files.txt"
if os.path.exists(mounted_report):
    result["mounted_report_exists"] = True
    result["mounted_report_mtime"] = int(os.path.getmtime(mounted_report))
    with open(mounted_report, "r", errors="replace") as f:
        lines = [l.strip() for l in f.readlines() if l.strip()]
        result["mounted_report_lines"] = len(lines)

# Check delta report
delta_report = "/home/ga/Reports/allocation_delta_report.txt"
if os.path.exists(delta_report):
    result["delta_report_exists"] = True
    result["delta_report_mtime"] = int(os.path.getmtime(delta_report))
    with open(delta_report, "r", errors="replace") as f:
        result["delta_report_content"] = f.read(8192)

print(json.dumps(result, indent=2))
with open("/tmp/delta_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/delta_result.json")
PYEOF

echo "=== Export complete ==="