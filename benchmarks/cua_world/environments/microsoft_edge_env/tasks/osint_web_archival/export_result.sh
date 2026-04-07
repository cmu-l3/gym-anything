#!/bin/bash
# Export script for OSINT Web Archival task
# Checks for existence and validity of MHTML files and catalog

echo "=== Exporting OSINT Web Archival Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python for robust validation
python3 << 'PYEOF'
import json
import os
import shutil
import sqlite3
import tempfile
import time

# --- Configuration ---
TASK_NAME = "osint_web_archival"
EVIDENCE_DIR = "/home/ga/Documents/OSINT_Evidence"
CATALOG_FILE = os.path.join(EVIDENCE_DIR, "evidence_catalog.txt")
START_TS_FILE = f"/tmp/task_start_ts_{TASK_NAME}.txt"
HISTORY_PATH = "/home/ga/.config/microsoft-edge/Default/History"
TARGETS = [
    {"filename": "cia_world_factbook.mhtml", "domain": "cia.gov"},
    {"filename": "fbi_most_wanted.mhtml", "domain": "fbi.gov"},
    {"filename": "ofac_sanctions.mhtml", "domain": "treasury.gov"}
]

# --- Helpers ---
def get_task_start_time():
    try:
        with open(START_TS_FILE, 'r') as f:
            return int(f.read().strip())
    except:
        return 0

def query_history(query):
    if not os.path.exists(HISTORY_PATH):
        return []
    tmp = tempfile.mktemp(suffix=".sqlite3")
    try:
        shutil.copy2(HISTORY_PATH, tmp)
        conn = sqlite3.connect(tmp)
        rows = conn.execute(query).fetchall()
        conn.close()
        return rows
    except Exception as e:
        print(f"History query error: {e}")
        return []
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def validate_mhtml(filepath):
    """
    Checks if file exists, is large enough, and has MHTML headers.
    Returns: (exists, valid_header, size_bytes, modified_after_start)
    """
    if not os.path.exists(filepath):
        return (False, False, 0, False)
    
    stat = os.stat(filepath)
    size = stat.st_size
    mtime = int(stat.st_mtime)
    
    # Check for MHTML signature
    is_mhtml = False
    try:
        with open(filepath, 'rb') as f:
            head = f.read(2048).decode('utf-8', errors='ignore')
            if 'MIME-Version:' in head and 'multipart/related' in head:
                is_mhtml = True
            # Also accept just multipart check if MIME-Version is deeper
            elif 'Content-Type: multipart/related' in head:
                is_mhtml = True
    except:
        pass
        
    return (True, is_mhtml, size, mtime > task_start)

# --- Main Execution ---
task_start = get_task_start_time()

# 1. Check Directory
dir_exists = os.path.isdir(EVIDENCE_DIR)

# 2. Check Files
file_results = {}
for target in TARGETS:
    fname = target['filename']
    fpath = os.path.join(EVIDENCE_DIR, fname)
    exists, valid_header, size, new = validate_mhtml(fpath)
    
    # Check History
    # We look for visits to the domain
    hist_rows = query_history(f"SELECT COUNT(*) FROM urls WHERE url LIKE '%{target['domain']}%'")
    visited = hist_rows[0][0] > 0 if hist_rows else False
    
    file_results[fname] = {
        "exists": exists,
        "valid_mhtml_header": valid_header,
        "size_bytes": size,
        "created_during_task": new,
        "domain_visited": visited
    }

# 3. Check Catalog
catalog_exists = os.path.exists(CATALOG_FILE)
catalog_content = ""
catalog_valid = False
catalog_size = 0
catalog_new = False

if catalog_exists:
    stat = os.stat(CATALOG_FILE)
    catalog_size = stat.st_size
    catalog_new = stat.st_mtime > task_start
    try:
        with open(CATALOG_FILE, 'r', errors='ignore') as f:
            catalog_content = f.read().lower()
            
        # Basic content check
        has_cia = "cia.gov" in catalog_content
        has_fbi = "fbi.gov" in catalog_content
        has_ofac = "treasury.gov" in catalog_content or "ofac" in catalog_content
        
        has_filenames = all(t['filename'].lower() in catalog_content for t in TARGETS)
        
        catalog_valid = has_cia and has_fbi and has_ofac and has_filenames
    except:
        pass

# 4. Compile Result
result = {
    "task_start": task_start,
    "directory_created": dir_exists,
    "files": file_results,
    "catalog": {
        "exists": catalog_exists,
        "valid_content": catalog_valid,
        "size_bytes": catalog_size,
        "created_during_task": catalog_new,
        "content_preview": catalog_content[:200]
    }
}

with open("/tmp/osint_web_archival_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="