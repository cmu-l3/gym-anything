#!/bin/bash
# Export script for sqlite_financial_artifact_parsing task

echo "=== Exporting results for sqlite_financial_artifact_parsing ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of the state before killing
DISPLAY=:1 scrot /tmp/financial_parsing_final.png 2>/dev/null || true

# Kill Autopsy to ensure autopsy.db is flushed and unlocked
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "sqlite_financial_artifact_parsing",
    "case_db_found": False,
    "logical_source_added": False,
    "ext_mismatch_detected": False,
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_exists": False,
    "summary_mtime": 0,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/financial_parsing_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Check for Autopsy DB
db_paths = glob.glob("/home/ga/Cases/Financial_Triage_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Financial_Triage_2024"
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    print(f"Found DB: {db_path}")

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()

        # Check data source (Logical Files)
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE name='logical_seizure' OR name='system_config.sys'")
            if cur.fetchone()[0] > 0:
                result["logical_source_added"] = True
        except Exception:
            pass

        # Check Extension Mismatch Artifact
        try:
            cur.execute("""
                SELECT COUNT(*) FROM blackboard_artifacts ba
                JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
                WHERE bat.type_name = 'TSK_EXT_MISMATCH'
            """)
            if cur.fetchone()[0] > 0:
                result["ext_mismatch_detected"] = True
        except Exception as e:
            result["error"] += f" | Mismatch check error: {e}"

        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# Check CSV Report
csv_path = "/home/ga/Reports/suspect_transactions.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        result["csv_content"] = f.read(16384)

# Check Summary Report
summary_path = "/home/ga/Reports/financial_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    result["summary_mtime"] = int(os.path.getmtime(summary_path))
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(4096)

# Save results safely
with open("/tmp/financial_parsing_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/financial_parsing_result.json")
PYEOF

echo "=== Export complete ==="