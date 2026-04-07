#!/bin/bash
echo "=== Exporting results for nested_archive_forensic_triage ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before killing the application
take_screenshot /tmp/task_final.png ga

echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "nested_archive_forensic_triage",
    "case_db_found": False,
    "data_sources": [],
    "image_names": [],
    "extracted_files": [],
    "exports_found": [],
    "report_exists": False,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/nested_archive_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate the autopsy.db for the specific case
db_paths = glob.glob("/home/ga/Cases/Archive_Triage_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Archive_Triage_2024"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    print(f"Found DB: {db_path}")

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        try:
            cur.execute("SELECT name FROM data_source_info")
            result["data_sources"] = [r["name"] for r in cur.fetchall()]
        except Exception:
            pass

        try:
            cur.execute("SELECT name FROM tsk_image_names")
            result["image_names"] = [r["name"] for r in cur.fetchall()]
        except Exception:
            pass

        try:
            cur.execute("SELECT name FROM tsk_files WHERE name IN ('server_backup.dat', 'payloads.zip', 'vm_disk_01.dd', 'usb_clone.dd')")
            result["extracted_files"] = [r["name"] for r in cur.fetchall()]
        except Exception:
            pass

        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# Check for successful file extraction to the host OS
export_dir = "/home/ga/Cases/Archive_Triage_2024/Export"
if os.path.isdir(export_dir):
    for f in ["vm_disk_01.dd", "usb_clone.dd"]:
        if os.path.exists(os.path.join(export_dir, f)):
            result["exports_found"].append(f)

# Evaluate the hash provenance report
report_path = "/home/ga/Reports/archive_provenance.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(4096)

with open(os.environ.get("TEMP_JSON", "/tmp/temp_result.json"), "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move payload safely
rm -f /tmp/nested_archive_result.json 2>/dev/null || sudo rm -f /tmp/nested_archive_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/nested_archive_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/nested_archive_result.json
chmod 666 /tmp/nested_archive_result.json 2>/dev/null || sudo chmod 666 /tmp/nested_archive_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="