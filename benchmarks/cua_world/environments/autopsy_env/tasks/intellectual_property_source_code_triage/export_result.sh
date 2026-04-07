#!/bin/bash
echo "=== Exporting IP Theft task results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Kill Autopsy to ensure SQLite DB locks are released
kill_autopsy
sleep 3

# Execute Python script to extract state and results safely
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task_start": 0,
    "case_db_found": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_hash_artifacts": 0,
    "manifest_exists": False,
    "manifest_mtime": 0,
    "manifest_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "screenshot_path": "/tmp/task_final.png",
    "error": ""
}

try:
    with open("/tmp/task_start_time") as f:
        result["task_start"] = int(f.read().strip())
except Exception:
    pass

# Check for Autopsy DB
db_paths = glob.glob("/home/ga/Cases/IP_Theft_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check Data Source
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except Exception:
            try:
                cur.execute("SELECT COUNT(*) FROM tsk_image_info")
                result["data_source_added"] = cur.fetchone()[0] > 0
            except:
                pass

        # Check Ingest (Files indexed)
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
            result["ingest_completed"] = cur.fetchone()[0] > 0
        except Exception:
            pass
            
        # Check Hash Artifacts
        try:
            cur.execute("""
                SELECT COUNT(*) FROM blackboard_artifacts ba
                JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
                WHERE bat.type_name LIKE '%HASH%' OR bat.type_name LIKE '%MD5%'
            """)
            result["db_hash_artifacts"] = cur.fetchone()[0]
        except Exception:
            pass

        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# Check Manifest
manifest_path = "/home/ga/Reports/source_code_manifest.csv"
if os.path.exists(manifest_path):
    result["manifest_exists"] = True
    result["manifest_mtime"] = int(os.path.getmtime(manifest_path))
    with open(manifest_path, "r", errors="replace") as f:
        result["manifest_content"] = f.read(1024 * 1024) # Up to 1MB

# Check Summary
summary_path = "/home/ga/Reports/ip_theft_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

# Write output safely
tmp_json = "/tmp/ip_theft_result_tmp.json"
with open(tmp_json, "w") as f:
    json.dump(result, f, indent=2)
os.chmod(tmp_json, 0o666)
os.rename(tmp_json, "/tmp/ip_theft_result.json")
PYEOF

echo "Result saved to /tmp/ip_theft_result.json"
echo "=== Export complete ==="