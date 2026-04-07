#!/bin/bash
# Export script for steganography_eof_triage task

echo "=== Exporting results for steganography_eof_triage ==="

source /workspace/scripts/task_utils.sh

# Take a screenshot right before closing
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to ensure all SQLite databases are cleanly written and locks released
kill_autopsy
sleep 3

# Evaluate the task results programmatically
python3 << 'PYEOF'
import json, os, csv, sqlite3, glob

result = {
    "case_db_found": False,
    "data_source_added": False,
    "ingest_completed": False,
    "extracted_count": 0,
    "gt_files": {},
    "agent_csv": {},
    "csv_exists": False,
    "summary_exists": False,
    "summary_content": "",
    "error": ""
}

# 1. Autopsy SQLite Database Checks
db_paths = glob.glob("/home/ga/Cases/Steganography_Triage_2024*/autopsy.db")
if db_paths:
    result["case_db_found"] = True
    db_path = db_paths[0]
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Check if they added the data source
        cur.execute("SELECT COUNT(*) FROM tsk_image_info")
        if cur.fetchone()[0] > 0:
            result["data_source_added"] = True
            
        # Check if ingest ran (by verifying MIME types exist)
        cur.execute("SELECT COUNT(*) FROM tsk_files WHERE meta_type=1 AND mime_type='image/jpeg'")
        if cur.fetchone()[0] > 0:
            result["ingest_completed"] = True
            
        conn.close()
    except Exception as e:
        result["error"] += f"DB Error: {e} | "

# 2. Extraction Directory & Ground Truth Calculation
# We calculate the TRUE answers based on what the agent *actually* extracted
extracted_dir = "/home/ga/Reports/extracted_jpegs"
if os.path.isdir(extracted_dir):
    for fname in os.listdir(extracted_dir):
        fpath = os.path.join(extracted_dir, fname)
        if os.path.isfile(fpath):
            try:
                with open(fpath, "rb") as f:
                    content = f.read()
                size = len(content)
                offset = content.rfind(b'\xff\xd9')
                extraneous = 0 if offset == -1 else size - (offset + 2)
                
                result["gt_files"][fname] = {
                    "size": size,
                    "last_eoi_offset": offset,
                    "extraneous_bytes": extraneous
                }
            except Exception:
                pass
    result["extracted_count"] = len(result["gt_files"])

# 3. Read Agent's CSV File
csv_path = "/home/ga/Reports/steg_analysis.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    try:
        with open(csv_path, "r", errors="replace") as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
            if lines:
                headers = [h.strip().upper() for h in lines[0].split('|')]
                for line in lines[1:]:
                    parts = [p.strip() for p in line.split('|')]
                    # Zip mapping up to the length of the shorter sequence
                    row = dict(zip(headers, parts))
                    fname = row.get("FILENAME", "")
                    if fname:
                        try:
                            result["agent_csv"][fname] = {
                                "size": int(row.get("FILE_SIZE", -1)),
                                "last_eoi_offset": int(row.get("LAST_EOI_OFFSET", -2)),
                                "extraneous_bytes": int(row.get("EXTRANEOUS_BYTES", -1))
                            }
                        except ValueError:
                            pass # Format mismatch (e.g. non-integer values)
    except Exception as e:
        result["error"] += f"CSV Parse Error: {e} | "

# 4. Read Summary File
sum_path = "/home/ga/Reports/steg_summary.txt"
if os.path.exists(sum_path):
    result["summary_exists"] = True
    try:
        with open(sum_path, "r", errors="replace") as f:
            result["summary_content"] = f.read(4096)
    except Exception:
        pass

# Write out everything for the verifier
with open("/tmp/steg_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Task results evaluated and exported to /tmp/steg_result.json"