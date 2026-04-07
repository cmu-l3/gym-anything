#!/bin/bash
echo "=== Exporting bulk_document_embedded_media_triage result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga
sleep 1

# Kill Autopsy to ensure SQLite database locks are released
kill_autopsy
sleep 3

# Execute Python script to extract verification data
python3 << 'PYEOF'
import json, os, sqlite3, glob

result = {
    "task": "bulk_document_embedded_media_triage",
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "ingest_completed": False,
    "db_embedded_images_count": 0,
    "db_parent_docs_count": 0,
    "db_extracted_images": [],
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "summary_exists": False,
    "summary_content": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/task_start_time.txt") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 1. Locate autopsy.db
db_paths = glob.glob("/home/ga/Cases/Document_Triage_2024*/autopsy.db")
if not db_paths:
    result["error"] = "autopsy.db not found for Document_Triage_2024"
    with open("/tmp/task_result.json", "w") as f:
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

    # Check Data Source (Logical File)
    try:
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        result["data_source_added"] = cur.fetchone()[0] > 0
    except Exception:
        pass

    # Check Embedded Media Extraction
    try:
        # Extracted files usually have parent_path containing the source document name
        cur.execute("""
            SELECT name, size, mime_type, parent_path, md5
            FROM tsk_files
            WHERE meta_type = 1 
              AND (mime_type LIKE 'image/%' OR lower(name) LIKE '%.jpg' OR lower(name) LIKE '%.png')
              AND (lower(parent_path) LIKE '%.pdf%' OR lower(parent_path) LIKE '%.doc%')
        """)
        rows = cur.fetchall()
        result["db_embedded_images_count"] = len(rows)
        
        extracted = []
        parent_docs = set()
        for r in rows:
            extracted.append({
                "name": r["name"],
                "size": r["size"],
                "mime_type": r["mime_type"],
                "parent_path": r["parent_path"],
                "md5": r["md5"]
            })
            # Try to extract the parent document name from parent_path (e.g. /000.zip/Digital_forensics.pdf/)
            parts = [p for p in r["parent_path"].split('/') if '.pdf' in p.lower() or '.doc' in p.lower()]
            if parts:
                parent_docs.add(parts[0])
                
        result["db_extracted_images"] = extracted
        result["db_parent_docs_count"] = len(parent_docs)
        if len(rows) > 0:
            result["ingest_completed"] = True
            
    except Exception as e:
        result["error"] += f" | DB query error: {e}"

    conn.close()
except Exception as e:
    result["error"] += f" | DB open error: {e}"

# 2. Check agent's CSV Report
csv_path = "/home/ga/Reports/embedded_media.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    with open(csv_path, "r", errors="replace") as f:
        result["csv_content"] = f.read(16384)

# 3. Check agent's Summary Report
summary_path = "/home/ga/Reports/embedded_summary.txt"
if os.path.exists(summary_path):
    result["summary_exists"] = True
    with open(summary_path, "r", errors="replace") as f:
        result["summary_content"] = f.read(2048)

print(json.dumps(result, indent=2))
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

# Ensure proper permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="