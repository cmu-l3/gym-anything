#!/bin/bash
# Export script for LOB Document Ingestion task
# Verifies database content and report file

set -e

echo "=== Exporting LOB Ingestion Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Path to the report
REPORT_PATH="/home/ga/Desktop/duplicate_report.txt"

# Use Python to inspect DB and generate result JSON
# We use Python/oracledb for robust BLOB handling and hashing
python3 << 'PYEOF'
import oracledb
import json
import os
import hashlib
import sys

# Configuration
DB_DSN = "localhost:1521/XEPDB1"
REPORT_PATH = "/home/ga/Desktop/duplicate_report.txt"
DATA_DIR = "/tmp/licenses"

result = {
    "directory_created": False,
    "directory_path_correct": False,
    "table_exists": False,
    "columns_correct": False,
    "row_count": 0,
    "blob_content_valid": False,
    "hashes_populated": False,
    "hashes_correct": False,
    "duplicate_pair_identified_in_db": False,
    "report_exists": False,
    "report_content": "",
    "errors": []
}

try:
    # Connect as SYSTEM to check Directory object
    conn_sys = oracledb.connect(user="system", password="OraclePassword123", dsn=DB_DSN)
    cur_sys = conn_sys.cursor()
    
    cur_sys.execute("SELECT directory_path FROM dba_directories WHERE directory_name = 'LICENSE_DIR'")
    row = cur_sys.fetchone()
    if row:
        result["directory_created"] = True
        # Normalize paths for comparison (remove trailing slashes)
        db_path = row[0].rstrip('/')
        if db_path == "/tmp/licenses":
            result["directory_path_correct"] = True
    
    cur_sys.close()
    conn_sys.close()

    # Connect as HR to check Table and Data
    conn_hr = oracledb.connect(user="hr", password="hr123", dsn=DB_DSN)
    cur_hr = conn_hr.cursor()

    # Check Table Existence
    cur_hr.execute("SELECT table_name FROM user_tables WHERE table_name = 'LICENSE_ARCHIVE'")
    if cur_hr.fetchone():
        result["table_exists"] = True

        # Check Columns
        cur_hr.execute("SELECT column_name, data_type FROM user_tab_cols WHERE table_name = 'LICENSE_ARCHIVE'")
        cols = {row[0]: row[1] for row in cur_hr.fetchall()}
        
        required_cols = {
            "FILE_CONTENT": "BLOB", 
            "FILE_HASH": "VARCHAR2", 
            "FILENAME": "VARCHAR2"
        }
        
        # Simple check: verify required columns exist and types match roughly
        cols_ok = True
        for name, dtype in required_cols.items():
            if name not in cols or dtype not in cols[name]:
                cols_ok = False
        result["columns_correct"] = cols_ok

        # Check Data
        cur_hr.execute("SELECT filename, file_hash, file_content FROM license_archive")
        rows = cur_hr.fetchall()
        result["row_count"] = len(rows)

        # Validate Content
        blobs_valid = 0
        hashes_valid = 0
        filenames_found = []
        hash_map = {}

        for filename, db_hash, blob_obj in rows:
            filenames_found.append(filename)
            
            # Read BLOB data
            if blob_obj:
                blob_data = blob_obj.read()
                if len(blob_data) > 0:
                    blobs_valid += 1
                    
                    # Calculate actual hash of BLOB
                    actual_hash = hashlib.sha256(blob_data).hexdigest().upper()
                    
                    # Verify DB stored hash matches actual hash
                    if db_hash and db_hash.upper() == actual_hash:
                        hashes_valid += 1
                    
                    hash_map[filename] = actual_hash

        if result["row_count"] == 5 and blobs_valid == 5:
            result["blob_content_valid"] = True
        
        if result["row_count"] == 5 and hashes_valid == 5:
            result["hashes_correct"] = True
            result["hashes_populated"] = True
        elif hashes_valid > 0:
            result["hashes_populated"] = True

        # Check for duplicates in DB
        # vendor_terms.txt and apache-2.0.txt should have same hash
        h1 = hash_map.get("vendor_terms.txt")
        h2 = hash_map.get("apache-2.0.txt")
        if h1 and h2 and h1 == h2:
            result["duplicate_pair_identified_in_db"] = True

    cur_hr.close()
    conn_hr.close()

except Exception as e:
    result["errors"].append(str(e))

# Check Report File
if os.path.exists(REPORT_PATH):
    result["report_exists"] = True
    try:
        with open(REPORT_PATH, 'r') as f:
            result["report_content"] = f.read()
    except Exception as e:
        result["errors"].append(f"Report read error: {e}")

# Save JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export completed.")
PYEOF

chmod 644 /tmp/task_result.json
cat /tmp/task_result.json
echo "=== Export Complete ==="