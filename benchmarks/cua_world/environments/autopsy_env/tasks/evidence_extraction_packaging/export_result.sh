#!/bin/bash
# Export script for evidence_extraction_packaging task

echo "=== Exporting results for evidence_extraction_packaging ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to release SQLite locks
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, hashlib

result = {
    "task": "evidence_extraction_packaging",
    "case_db_found": False,
    "data_source_added": False,
    "ingest_completed": False,
    "extracted_files": {},
    "extracted_file_count": 0,
    "manifest_exists": False,
    "manifest_mtime": 0,
    "manifest_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/evidence_extraction_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Evidence_Packaging_2024*/autopsy.db")
if not db_paths:
    # Try broader search
    db_paths = [p for p in glob.glob("/home/ga/Cases/*/autopsy.db") if "Evidence_Packaging" in p]

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
            
        conn.close()
    except Exception as e:
        result["error"] += f"DB error: {str(e)} "
else:
    result["error"] += "autopsy.db not found. "

# Check extracted files
export_dir = "/home/ga/Reports/extracted_evidence"
if os.path.exists(export_dir) and os.path.isdir(export_dir):
    for root, dirs, files in os.walk(export_dir):
        for f in files:
            filepath = os.path.join(root, f)
            try:
                with open(filepath, 'rb') as file_obj:
                    content = file_obj.read()
                    md5 = hashlib.md5(content).hexdigest()
                    sha256 = hashlib.sha256(content).hexdigest()
                    result["extracted_files"][f] = {
                        "md5": md5,
                        "sha256": sha256,
                        "size": len(content),
                        "mtime": int(os.path.getmtime(filepath))
                    }
            except Exception as e:
                pass
    result["extracted_file_count"] = len(result["extracted_files"])

# Check manifest
manifest_path = "/home/ga/Reports/evidence_manifest.txt"
if os.path.exists(manifest_path):
    result["manifest_exists"] = True
    result["manifest_mtime"] = int(os.path.getmtime(manifest_path))
    try:
        with open(manifest_path, "r", errors="replace") as f:
            result["manifest_content"] = f.read(16384)
    except Exception:
        pass

# Check summary
summary_path = "/home/ga/Reports/packaging_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    try:
        with open(summary_path, "r", errors="replace") as f:
            result["summary_content"] = f.read(4096)
    except Exception:
        pass

print(json.dumps(result, indent=2))
with open("/tmp/evidence_extraction_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "=== Export complete ==="