#!/bin/bash
# Export script for obfuscated_fragment_reconstruction task
echo "=== Exporting results for obfuscated_fragment_reconstruction ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga
sleep 1

# Kill Autopsy to ensure SQLite databases are flushed and unlocked
echo "Closing Autopsy to release DB locks..."
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "obfuscated_fragment_reconstruction",
    "case_db_found": False,
    "data_source_added": False,
    "db_tagged_items_count": 0,
    "reconstructed_file_exists": False,
    "reconstructed_file_mtime": 0,
    "reconstructed_file_size": 0,
    "reconstructed_md5": "",
    "gt_hash": "",
    "report_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# 1. Read start time
try:
    with open("/tmp/obfuscated_fragment_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 2. Read Ground Truth Hash
try:
    with open("/var/lib/app/ground_truth/original_hash.txt") as f:
        result["gt_hash"] = f.read().strip()
except Exception as e:
    result["error"] += f" | Failed reading GT hash: {e}"

# 3. Query Autopsy Database
db_paths = glob.glob("/home/ga/Cases/Fragment_Recovery_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check data source
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except:
            pass
            
        # Check tagging (agent must use the GUI to tag the fragments)
        try:
            cur.execute("SELECT COUNT(*) FROM content_tags")
            result["db_tagged_items_count"] = cur.fetchone()[0]
        except:
            pass
            
        conn.close()
    except Exception as e:
        result["error"] += f" | DB query error: {e}"

# 4. Check Reconstructed Image
recon_path = "/home/ga/Reports/reconstructed_evidence.jpg"
if os.path.exists(recon_path):
    result["reconstructed_file_exists"] = True
    result["reconstructed_file_mtime"] = int(os.path.getmtime(recon_path))
    result["reconstructed_file_size"] = os.path.getsize(recon_path)
    
    # Calculate MD5
    md5_hash = hashlib.md5()
    with open(recon_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            md5_hash.update(chunk)
    result["reconstructed_md5"] = md5_hash.hexdigest()

# 5. Check Forensic Report
report_path = "/home/ga/Reports/reconstruction_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["report_content"] = f.read(8192)

# Write output safely
print(json.dumps(result, indent=2))
with open("/tmp/obfuscated_fragment_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/obfuscated_fragment_result.json")
PYEOF

chmod 666 /tmp/obfuscated_fragment_result.json 2>/dev/null || true
echo "=== Export complete ==="