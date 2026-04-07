#!/bin/bash
# Export script for split_image_anti_forensics_reconstruction task

echo "=== Exporting results for split_image_reconstruction ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final_state.png ga

# Kill Autopsy to release SQLite locks
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "split_image_anti_forensics_reconstruction",
    "case_db_found": False,
    "data_source_added": False,
    "ingest_completed": False,
    "restored_dd_exists": False,
    "restored_dd_size": 0,
    "restored_dd_md5": "",
    "log_exists": False,
    "log_content": "",
    "csv_exists": False,
    "csv_content": "",
    "start_time": 0,
    "error": ""
}

# 1. Start Time
try:
    with open("/tmp/reconstruction_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 2. Check Restored Image
restored_path = "/home/ga/evidence/restored.dd"
if os.path.exists(restored_path):
    result["restored_dd_exists"] = True
    result["restored_dd_size"] = os.path.getsize(restored_path)
    
    # Calculate MD5 (if < 500MB to avoid timeout, typically 6MB)
    if result["restored_dd_size"] < 500000000:
        with open(restored_path, 'rb') as f:
            result["restored_dd_md5"] = hashlib.md5(f.read()).hexdigest()

# 3. Check Autopsy DB
db_paths = glob.glob("/home/ga/Cases/Fragment_Recovery_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check data source
        try:
            cur.execute("SELECT name FROM data_source_info")
            rows = cur.fetchall()
            names = [r[0].lower() for r in rows]
            if any('restored.dd' in n for n in names):
                result["data_source_added"] = True
            elif rows:
                result["data_source_added"] = True # Partial credit if they named it differently
        except Exception:
            try:
                cur.execute("SELECT name FROM tsk_image_info")
                rows = cur.fetchall()
                names = [r[0].lower() for r in rows]
                if any('restored.dd' in n for n in names):
                    result["data_source_added"] = True
            except Exception:
                pass
                
        # Check ingest
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass
            
        conn.close()
    except Exception as e:
        result["error"] += f" | DB Error: {e}"

# 4. Check Log File
log_path = "/home/ga/Reports/image_reconstruction_log.txt"
if os.path.exists(log_path):
    result["log_exists"] = True
    with open(log_path, "r", errors="replace") as f:
        result["log_content"] = f.read(4096)

# 5. Check CSV File
csv_path = "/home/ga/Reports/hidden_chunk_files.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    with open(csv_path, "r", errors="replace") as f:
        result["csv_content"] = f.read(16384)

# Write results
print(json.dumps(result, indent=2))
with open("/tmp/reconstruction_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "=== Export complete ==="