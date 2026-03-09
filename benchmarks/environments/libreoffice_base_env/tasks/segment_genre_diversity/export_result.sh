#!/bin/bash
echo "=== Exporting segment_genre_diversity results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Close LibreOffice to flush HSQLDB changes to the ODB file
kill_libreoffice

# 3. Check file timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"
ODB_MODIFIED="false"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 4. Extract HSQLDB script and verify data using Python
# We do the heavy lifting here because we have access to both the ODB and the original SQLite source
# inside the container.

python3 -c "
import zipfile
import sqlite3
import re
import json
import os
import sys

# Paths
odb_path = '/home/ga/chinook.odb'
sqlite_path = '/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite'
output_json = '/tmp/task_result.json'

result = {
    'odb_exists': False,
    'odb_modified': $ODB_MODIFIED,
    'schema_correct': False,
    'data_clean': False, # No nulls
    'casual_precision': 0.0,
    'eclectic_recall': 0.0,
    'total_customers': 0,
    'errors': []
}

if not os.path.exists(odb_path):
    result['errors'].append('ODB file not found')
    with open(output_json, 'w') as f:
        json.dump(result, f)
    sys.exit(0)

result['odb_exists'] = True

# --- Step A: Calculate Ground Truth from SQLite ---
try:
    conn = sqlite3.connect(sqlite_path)
    cursor = conn.cursor()
    
    # Query: Count distinct genres per customer
    # Tables: Customer(CustomerId) -> Invoice(InvoiceId, CustomerId) -> InvoiceLine(InvoiceId, TrackId) -> Track(TrackId, GenreId)
    query = '''
        SELECT c.CustomerId, COUNT(DISTINCT t.GenreId) as GenreCount
        FROM Customer c
        JOIN Invoice i ON c.CustomerId = i.CustomerId
        JOIN InvoiceLine il ON i.InvoiceId = il.InvoiceId
        JOIN Track t ON il.TrackId = t.TrackId
        GROUP BY c.CustomerId
    '''
    cursor.execute(query)
    rows = cursor.fetchall()
    
    ground_truth = {}
    # Get all customer IDs (some might have 0 purchases, though unlikely in Chinook)
    cursor.execute('SELECT CustomerId FROM Customer')
    all_ids = [r[0] for r in cursor.fetchall()]
    
    # Map counts
    counts = {r[0]: r[1] for r in rows}
    
    for cid in all_ids:
        cnt = counts.get(cid, 0)
        ground_truth[cid] = 'Eclectic' if cnt >= 4 else 'Casual'
        
    conn.close()
    result['total_customers'] = len(ground_truth)
    
except Exception as e:
    result['errors'].append(f'Ground truth calculation failed: {str(e)}')
    with open(output_json, 'w') as f:
        json.dump(result, f)
    sys.exit(0)

# --- Step B: Extract and Parse HSQLDB Script from ODB ---
try:
    hsql_script = ''
    with zipfile.ZipFile(odb_path, 'r') as zf:
        # HSQLDB data is in 'database/script'
        if 'database/script' in zf.namelist():
            hsql_script = zf.read('database/script').decode('utf-8', errors='ignore')
        else:
            result['errors'].append('database/script not found in ODB')
            
    if not hsql_script:
        raise Exception('Empty script')

    # Check Schema: Look for CREATE TABLE or ALTER TABLE adding Segment
    # HSQLDB usually reconstructs the schema in the script file as CREATE TABLE statements
    # Look for: CREATE TABLE PUBLIC.\"Customer\" (... \"Segment\" VARCHAR...)
    
    # Regex to find Customer table definition
    # It might be split across lines
    customer_def_match = re.search(r'CREATE TABLE PUBLIC\.\"Customer\"\s*\((.*?)\)', hsql_script, re.DOTALL)
    
    schema_found = False
    if customer_def_match:
        columns = customer_def_match.group(1)
        if '\"Segment\"' in columns or 'Segment' in columns:
            # Check type (VARCHAR/LONGVARCHAR)
            if 'VARCHAR' in columns:
                schema_found = True
    
    result['schema_correct'] = schema_found
    
    # Parse Data: Look for INSERT INTO PUBLIC.\"Customer\" VALUES(...)
    # We need to parse values to map ID -> Segment
    
    agent_data = {}
    
    # Regex for INSERT statements
    # Format: INSERT INTO PUBLIC."Customer" VALUES(1,'Luís','Gonçalves',...,'Eclectic')
    # Note: Values are comma separated, strings in single quotes.
    
    insert_pattern = re.compile(r'INSERT INTO PUBLIC\.\"Customer\" VALUES\((.+?)\)')
    
    for line in hsql_script.splitlines():
        if 'INSERT INTO PUBLIC."Customer"' in line:
            match = insert_pattern.search(line)
            if match:
                val_str = match.group(1)
                # Naive CSV parsing logic for SQL values (handles quoted strings roughly)
                # We assume ID is first (integer) and Segment is last (string)
                
                # Split by comma, respecting quotes is hard with simple split. 
                # But HSQLDB script format is very regular.
                # Let's use a simpler approach: Extract ID (first item) and Segment (last item)
                
                parts = val_str.split(',')
                try:
                    cid = int(parts[0])
                    
                    # Last part might be the segment. Remove quotes.
                    # Warning: If user added column in middle, this fails. 
                    # But usually ALTER ADD COLUMN adds to end.
                    # Or if recreated, usually follows schema order.
                    
                    # Better: Scan for 'Eclectic' or 'Casual' in the line
                    segment_val = None
                    if \"'Eclectic'\" in line:
                        segment_val = 'Eclectic'
                    elif \"'Casual'\" in line:
                        segment_val = 'Casual'
                    else:
                        segment_val = 'NULL' # Or strictly missing
                        
                    agent_data[cid] = segment_val
                except:
                    continue

    # --- Step C: Compare ---
    
    correct_casual = 0
    total_casual_gt = 0
    correct_eclectic = 0
    total_eclectic_gt = 0
    null_values = 0
    
    for cid, expected in ground_truth.items():
        actual = agent_data.get(cid)
        
        if actual is None or actual == 'NULL':
            null_values += 1
            continue
            
        if expected == 'Casual':
            total_casual_gt += 1
            if actual == 'Casual':
                correct_casual += 1
        elif expected == 'Eclectic':
            total_eclectic_gt += 1
            if actual == 'Eclectic':
                correct_eclectic += 1

    result['data_clean'] = (null_values == 0) and (len(agent_data) == len(ground_truth))
    
    if total_casual_gt > 0:
        result['casual_precision'] = correct_casual / total_casual_gt
    else:
        result['casual_precision'] = 1.0
        
    if total_eclectic_gt > 0:
        result['eclectic_recall'] = correct_eclectic / total_eclectic_gt
    else:
        result['eclectic_recall'] = 1.0
        
    result['stats'] = {
        'total_gt': len(ground_truth),
        'agent_records': len(agent_data),
        'correct_casual': correct_casual,
        'correct_eclectic': correct_eclectic
    }

except Exception as e:
    result['errors'].append(f'Analysis failed: {str(e)}')

with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)
"

# 5. Move results to final location
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "Export complete. Results:"
cat /tmp/final_result.json