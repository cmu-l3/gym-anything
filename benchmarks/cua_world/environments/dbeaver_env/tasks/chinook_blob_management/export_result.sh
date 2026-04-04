#!/bin/bash
# Export script for chinook_blob_management task

echo "=== Exporting Chinook BLOB Management Result ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_IMAGE="/home/ga/Documents/exports/verified_badge.png"
DDL_SCRIPT="/home/ga/Documents/scripts/badge_schema.sql"
SOURCE_HASH_FILE="/tmp/source_image_hash.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Source Hash
SOURCE_HASH=""
if [ -f "$SOURCE_HASH_FILE" ]; then
    SOURCE_HASH=$(cat "$SOURCE_HASH_FILE")
fi

# 2. Check Exported File
EXPORT_EXISTS="false"
EXPORT_HASH=""
if [ -f "$EXPORT_IMAGE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_HASH=$(sha256sum "$EXPORT_IMAGE" | awk '{print $1}')
fi

# 3. Check DDL Script
DDL_EXISTS="false"
DDL_CONTENT=""
if [ -f "$DDL_SCRIPT" ]; then
    DDL_EXISTS="true"
    DDL_CONTENT=$(cat "$DDL_SCRIPT" | head -n 20) # Grab first 20 lines for rough check
fi

# 4. Check Database State (Table, Columns, Data, BLOB integrity)
# We use a python script to handle BLOB extraction reliably
echo "Inspecting database state..."

python3 << PYEOF > /tmp/db_inspection.json
import sqlite3
import hashlib
import json
import sys

db_path = "$DB_PATH"
result = {
    "table_exists": False,
    "columns_correct": False,
    "fk_exists": False,
    "record_exists": False,
    "blob_hash": "",
    "issue_date_correct": False,
    "columns_found": [],
    "error": ""
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Check table existence
    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='employee_badges'")
    if cursor.fetchone()[0] > 0:
        result["table_exists"] = True
        
        # Check columns
        cursor.execute("PRAGMA table_info(employee_badges)")
        cols = cursor.fetchall()
        # Format: (cid, name, type, notnull, dflt_value, pk)
        col_names = [c[1].lower() for c in cols]
        result["columns_found"] = col_names
        
        required_cols = {'badgeid', 'employeeid', 'badgedata', 'issuedate'}
        if required_cols.issubset(set(col_names)):
            result["columns_correct"] = True
            
        # Check FK
        cursor.execute("PRAGMA foreign_key_list(employee_badges)")
        fks = cursor.fetchall()
        # Format: (id, seq, table, from, to, on_update, on_delete, match)
        for fk in fks:
            if fk[2].lower() == 'employees' and fk[3].lower() == 'employeeid':
                result["fk_exists"] = True
                break
                
        # Check Record and BLOB
        cursor.execute("SELECT BadgeData, IssueDate FROM employee_badges WHERE EmployeeId=1")
        row = cursor.fetchone()
        if row:
            result["record_exists"] = True
            blob_data = row[0]
            issue_date = row[1]
            
            if issue_date == '2024-01-01':
                result["issue_date_correct"] = True
                
            if blob_data:
                # Calculate SHA256 of the BLOB
                if isinstance(blob_data, str):
                     # In case it was stored as text/hex erroneously
                     blob_bytes = blob_data.encode('utf-8')
                else:
                     blob_bytes = blob_data
                
                result["blob_hash"] = hashlib.sha256(blob_bytes).hexdigest()

    conn.close()
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Merge results
cat << JSONEOF > /tmp/task_result.json
{
    "source_hash": "$SOURCE_HASH",
    "export_exists": $EXPORT_EXISTS,
    "export_hash": "$EXPORT_HASH",
    "ddl_exists": $DDL_EXISTS,
    "ddl_content_preview": "$(echo "$DDL_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
    "db_state": $(cat /tmp/db_inspection.json),
    "timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="