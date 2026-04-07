#!/bin/bash
# Export script for legal_constraint_media_extraction task

echo "=== Exporting results for legal_constraint_media_extraction ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Kill Autopsy to release DB locks
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib, csv

result = {
    "task": "legal_constraint_media_extraction",
    "db_found": False,
    "ds_added": False,
    "exported_hashes": [],
    "exported_file_count": 0,
    "csv_exists": False,
    "csv_headers": [],
    "csv_rows": 0,
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 1. Check Autopsy Case Database
db_paths = glob.glob("/home/ga/Cases/Warrant_Compliance_2024*/autopsy.db")
if db_paths:
    result["db_found"] = True
    db_path = db_paths[0]
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["ds_added"] = cur.fetchone()[0] > 0
        conn.close()
    except Exception as e:
        result["error"] += f" | DB check error: {e}"

# 2. Hash Exported Media
export_dir = "/home/ga/Reports/Allocated_Media"
exported_hashes = []
if os.path.isdir(export_dir):
    for f in os.listdir(export_dir):
        p = os.path.join(export_dir, f)
        if os.path.isfile(p):
            try:
                with open(p, "rb") as fl:
                    h = hashlib.md5(fl.read()).hexdigest()
                    exported_hashes.append(h)
            except Exception:
                pass
result["exported_hashes"] = exported_hashes
result["exported_file_count"] = len(exported_hashes)

# 3. Read Manifest CSV
csv_path = "/home/ga/Reports/media_manifest.csv"
if os.path.isfile(csv_path):
    result["csv_exists"] = True
    try:
        with open(csv_path, 'r', errors='ignore') as f:
            reader = csv.reader(f)
            # Find the first non-empty row as header
            for row in reader:
                if any(cell.strip() for cell in row):
                    result["csv_headers"] = [c.strip() for c in row]
                    break
            # Count remaining valid data rows
            result["csv_rows"] = sum(1 for row in reader if any(c.strip() for c in row))
    except Exception as e:
        result["error"] += f" | CSV parse error: {e}"

# Safe write via Temp file
import tempfile, shutil
temp_json = tempfile.NamedTemporaryFile(delete=False, mode='w', suffix='.json')
json.dump(result, temp_json, indent=2)
temp_json.close()

os.system(f"chmod 666 {temp_json.name}")
os.system(f"cp {temp_json.name} /tmp/legal_constraint_result.json")
os.remove(temp_json.name)

print("Export Complete. Result data:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="