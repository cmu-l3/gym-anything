#!/bin/bash
# Export script for communications_network_graph_analysis task

echo "=== Exporting results for communications_network_graph_analysis ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE killing autopsy
take_screenshot /tmp/task_final_state.png ga

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 3

# ── Gather all results via Python ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "communications_network_graph_analysis",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "email_artifacts_found": 0,
    "report_file_exists": False,
    "report_mtime": 0,
    "report_content": "",
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/network_analysis_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Network_Analysis_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for case Network_Analysis_2024"
    print(json.dumps(result, indent=2))
    with open("/tmp/network_analysis_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
print(f"Found DB: {db_path}")
result["case_db_found"] = True
result["case_name_matches"] = True

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Check data source was added
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Check for Email artifacts
    try:
        # 2 = TSK_EMAIL_MSG in blackboard_artifact_types
        cur.execute("""
            SELECT COUNT(*) FROM blackboard_artifacts ba
            JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
            WHERE bat.type_name = 'TSK_EMAIL_MSG'
        """)
        result["email_artifacts_found"] = cur.fetchone()[0]
    except Exception as e:
        result["error"] += f" | DB query error for email artifacts: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check agent's report file
report_path = "/home/ga/Reports/communicator_analysis.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        content = f.read(8192)
    result["report_content"] = content
    print(f"Report file found: {len(content)} chars")
else:
    print("Report file not found")

print(json.dumps(result, indent=2))
with open("/tmp/network_analysis_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/network_analysis_result.json")
PYEOF

echo "=== Export complete ==="