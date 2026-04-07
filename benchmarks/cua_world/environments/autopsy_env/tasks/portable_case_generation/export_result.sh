#!/bin/bash
# Export script for portable_case_generation task

echo "=== Exporting results for portable_case_generation ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before killing Autopsy
take_screenshot /tmp/task_final_state.png

# Kill Autopsy to release SQLite locks
echo "Killing Autopsy to release DB lock..."
kill_autopsy
sleep 4

# Run python script to extract database insights and validate output
python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "portable_case_generation",
    "case_db_found": False,
    "data_source_added": False,
    "custom_tag_found": False,
    "tagged_items_count": 0,
    "memo_exists": False,
    "memo_valid": False,
    "memo_parsed_dir": "",
    "portable_case_db_found": False,
    "portable_case_valid": False,
    "portable_case_files_exported": 0,
    "start_time": 0,
    "error": ""
}

# Read start time
try:
    with open("/tmp/portable_case_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# ==========================================
# 1. Inspect Main Autopsy Case Database
# ==========================================
db_paths = glob.glob("/home/ga/Cases/Evidence_Handover_2024*/autopsy.db")
if not db_paths:
    result["error"] += "Main autopsy.db not found for Evidence_Handover_2024. "
else:
    db_path = db_paths[0]
    result["case_db_found"] = True
    print(f"Found Main DB: {db_path}")

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()

        # Check data source was added
        cur.execute("SELECT COUNT(*) FROM data_source_info")
        if cur.fetchone()[0] > 0:
            result["data_source_added"] = True

        # Check for the custom tag
        cur.execute("SELECT tag_name_id, display_name FROM tag_names WHERE display_name = 'Investigator_Review'")
        tag_row = cur.fetchone()
        if tag_row:
            result["custom_tag_found"] = True
            tag_id = tag_row["tag_name_id"]
            
            # Count how many items were tagged
            cur.execute("SELECT COUNT(*) FROM content_tags WHERE tag_name_id = ?", (tag_id,))
            result["tagged_items_count"] = cur.fetchone()[0]

        conn.close()
    except Exception as e:
        result["error"] += f"Main DB error: {e}. "

# ==========================================
# 2. Parse Handover Memo
# ==========================================
memo_path = "/home/ga/Reports/handover_memo.txt"
pc_dir_from_memo = ""

if os.path.exists(memo_path):
    result["memo_exists"] = True
    try:
        with open(memo_path, "r", errors="replace") as f:
            content = f.read()
            
        # Extract PORTABLE_CASE_DIR
        match = re.search(r"PORTABLE_CASE_DIR:\s*(.+)", content)
        if match:
            pc_dir_from_memo = match.group(1).strip()
            result["memo_parsed_dir"] = pc_dir_from_memo
            
        # Basic validation of other fields
        if "Evidence_Handover_2024" in content and "Investigator_Review" in content:
            result["memo_valid"] = True
    except Exception as e:
        result["error"] += f"Memo parsing error: {e}. "

# ==========================================
# 3. Locate and Validate Portable Case
# ==========================================
# If memo parsing failed or directory is wrong, search the filesystem fallback
portable_dbs = []

if pc_dir_from_memo and os.path.isdir(pc_dir_from_memo):
    portable_dbs = glob.glob(os.path.join(pc_dir_from_memo, "*.aut")) + glob.glob(os.path.join(pc_dir_from_memo, "autopsy.db"))

# Fallback: search anywhere for a Portable Case DB if not found via memo
if not portable_dbs:
    portable_dbs = glob.glob("/home/ga/**/*Portable*/*.aut", recursive=True) + glob.glob("/home/ga/**/*Portable*/autopsy.db", recursive=True)

if portable_dbs:
    pc_db_path = portable_dbs[0]
    result["portable_case_db_found"] = True
    pc_root_dir = os.path.dirname(pc_db_path)
    print(f"Found Portable Case DB: {pc_db_path}")

    try:
        pc_conn = sqlite3.connect(f"file:{pc_db_path}?mode=ro", uri=True)
        pc_cur = pc_conn.cursor()
        
        # Verify the custom tag made it to the portable case
        pc_cur.execute("SELECT COUNT(*) FROM tag_names WHERE display_name = 'Investigator_Review'")
        if pc_cur.fetchone()[0] > 0:
            result["portable_case_valid"] = True
            
        pc_conn.close()
    except Exception as e:
        result["error"] += f"Portable DB error: {e}. "
        
    # Verify files were actually exported to the Portable Case folder
    # Autopsy Portable Cases store exported files under a directory structure
    exported_files = 0
    for root, dirs, files in os.walk(pc_root_dir):
        for file in files:
            if file.lower().endswith(('.jpg', '.jpeg')):
                exported_files += 1
    result["portable_case_files_exported"] = exported_files

print(json.dumps(result, indent=2))
with open("/tmp/portable_case_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/portable_case_result.json")
PYEOF

echo "=== Export complete ==="