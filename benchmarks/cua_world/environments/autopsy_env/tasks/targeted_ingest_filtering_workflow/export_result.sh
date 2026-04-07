#!/bin/bash
# Export script for targeted_ingest_filtering_workflow task

echo "=== Exporting results for targeted_ingest_filtering_workflow ==="

source /workspace/scripts/task_utils.sh

# ── Kill Autopsy to release SQLite lock ───────────────────────────────────────
kill_autopsy
sleep 3

# ── Gather results via Python ─────────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "targeted_ingest_filtering_workflow",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "filter_logged": False,
    "in_scope_hashed_count": 0,
    "out_of_scope_hashed_count": 0,
    "in_scope_mime_count": 0,
    "out_of_scope_mime_count": 0,
    "total_files_count": 0,
    "audit_report_exists": False,
    "audit_report_mtime": 0,
    "audit_report_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/targeted_ingest_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Targeted_Ingest_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Targeted_Ingest_2024"
    with open("/tmp/targeted_ingest_result.json", "w") as f:
        json.dump(result, f, indent=2)
    import sys; sys.exit(0)

db_path = db_paths[0]
result["case_db_found"] = True
result["case_name_matches"] = True
print(f"Found DB: {db_path}")

try:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Data source check
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Total files check
    try:
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND dir_flags=1")
        result["total_files_count"] = cur.fetchone()[0]
    except Exception:
        pass

    # Hash and MIME counts check
    in_scope_exts = ("%.txt", "%.pdf", "%.doc", "%.jpg", "%.jpeg")
    like_clauses = " OR ".join([f"lower(name) LIKE '{ext}'" for ext in in_scope_exts])
    
    try:
        # In-scope hashed count
        cur.execute(f"SELECT COUNT(*) FROM tsk_files WHERE md5 IS NOT NULL AND ({like_clauses}) AND meta_type=1 AND dir_flags=1")
        result["in_scope_hashed_count"] = cur.fetchone()[0]

        # Out-of-scope hashed count
        cur.execute(f"SELECT COUNT(*) FROM tsk_files WHERE md5 IS NOT NULL AND NOT ({like_clauses}) AND meta_type=1 AND dir_flags=1 AND name NOT IN ('.', '..')")
        result["out_of_scope_hashed_count"] = cur.fetchone()[0]

        # In-scope mime populated
        cur.execute(f"SELECT COUNT(*) FROM tsk_files WHERE mime_type IS NOT NULL AND mime_type != '' AND ({like_clauses}) AND meta_type=1 AND dir_flags=1")
        result["in_scope_mime_count"] = cur.fetchone()[0]

        # Out-of-scope mime populated
        cur.execute(f"SELECT COUNT(*) FROM tsk_files WHERE mime_type IS NOT NULL AND mime_type != '' AND NOT ({like_clauses}) AND meta_type=1 AND dir_flags=1 AND name NOT IN ('.', '..')")
        result["out_of_scope_mime_count"] = cur.fetchone()[0]

    except Exception as e:
        result["error"] += f" | DB query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# Check logs for the filter name
try:
    log_files = glob.glob("/home/ga/.autopsy/dev/var/log/autopsy.log*")
    for lf in log_files:
        with open(lf, "r", errors="ignore") as f:
            content = f.read().upper()
            if "WARRANT_SCOPE" in content:
                result["filter_logged"] = True
                break
except Exception as e:
    result["error"] += f" | Log check error: {e}"

# Audit report
report_path = "/home/ga/Reports/filter_audit.txt"
if os.path.exists(report_path):
    result["audit_report_exists"] = True
    result["audit_report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        content = f.read(8192)
    result["audit_report_content"] = content
    print(f"Report file: {len(content)} chars")

print(json.dumps(result, indent=2))
with open("/tmp/targeted_ingest_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/targeted_ingest_result.json")
PYEOF

echo "=== Export complete ==="