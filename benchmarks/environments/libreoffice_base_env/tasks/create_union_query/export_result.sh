#!/bin/bash
set -e
echo "=== Exporting create_union_query task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Step 1: Force Save and Close LibreOffice ---
# We need to ensure the ODB file is flushed to disk before analyzing it.
# Attempt to save via shortcut
echo "Saving database..."
DISPLAY=:1 xdotool key ctrl+s
sleep 2

# Kill LibreOffice to release file locks and ensure zip archive is finalized
kill_libreoffice

# --- Step 2: Check File Modification ---
ODB_PATH="/home/ga/chinook.odb"
FILE_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# --- Step 3: Analyze ODB Content ---
# The ODB file is a ZIP. We extract content.xml to find the query definition.
# Then we try to run that SQL against the reference SQLite DB to verify correctness.

mkdir -p /tmp/odb_analysis
RESULT_JSON="/tmp/task_result.json"

# Python script to analyze the ODB and run the query
python3 -c "
import zipfile
import xml.etree.ElementTree as ET
import sqlite3
import json
import os
import sys
import re

result = {
    'file_modified': '$FILE_MODIFIED' == 'true',
    'query_found': False,
    'query_name': '',
    'query_sql': '',
    'uses_union': False,
    'has_contact_type': False,
    'execution_success': False,
    'row_count': 0,
    'columns': [],
    'error': ''
}

try:
    odb_path = '/home/ga/chinook.odb'
    if not os.path.exists(odb_path):
        result['error'] = 'ODB file not found'
        raise Exception('ODB file missing')

    # 1. Extract content.xml from ODB
    with zipfile.ZipFile(odb_path, 'r') as z:
        content_xml = z.read('content.xml')

    # 2. Parse XML to find query
    root = ET.fromstring(content_xml)
    
    # Namespaces usually used in ODB
    ns = {
        'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
        'xlink': 'http://www.w3.org/1999/xlink'
    }

    # Find query by name (case insensitive search)
    queries = root.findall('.//db:query', ns)
    target_query = None
    
    for q in queries:
        name = q.get('{urn:oasis:names:tc:opendocument:xmlns:database:1.0}name')
        if name and 'allcontact' in name.lower().replace(' ', ''):
            target_query = q
            result['query_name'] = name
            break
            
    if target_query is not None:
        result['query_found'] = True
        command = target_query.get('{urn:oasis:names:tc:opendocument:xmlns:database:1.0}command', '')
        result['query_sql'] = command
        
        # Static Analysis
        sql_upper = command.upper()
        if 'UNION' in sql_upper:
            result['uses_union'] = True
        
        # Check for literal column 'Customer' or 'Employee'
        if \"'Customer'\" in command or \"'Employee'\" in command:
            result['has_contact_type'] = True
            
        # 3. Dynamic Verification: Run against SQLite
        # We need to adapt the SQL slightly if needed, but standard SQL usually works on both
        sqlite_db = '/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite'
        conn = sqlite3.connect(sqlite_db)
        cursor = conn.cursor()
        
        try:
            cursor.execute(command)
            rows = cursor.fetchall()
            result['row_count'] = len(rows)
            result['execution_success'] = True
            
            # Get column names from description
            if cursor.description:
                result['columns'] = [d[0] for d in cursor.description]
                
        except Exception as e:
            result['error'] = f'SQL Execution Error: {str(e)}'
            # Fallback: Attempt to strip double quotes if execution failed (SQLite is loose but strict on some things)
            try:
                clean_command = command.replace('\"', '')
                cursor.execute(clean_command)
                rows = cursor.fetchall()
                result['row_count'] = len(rows)
                result['execution_success'] = True
                result['error'] = 'Success after stripping quotes'
                if cursor.description:
                    result['columns'] = [d[0] for d in cursor.description]
            except:
                pass
                
        conn.close()

except Exception as e:
    result['error'] = str(e)

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=4)
"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Set permissions for the result file so verifier can read it
chmod 644 "$RESULT_JSON"

echo "Result JSON content:"
cat "$RESULT_JSON"
echo "=== Export complete ==="