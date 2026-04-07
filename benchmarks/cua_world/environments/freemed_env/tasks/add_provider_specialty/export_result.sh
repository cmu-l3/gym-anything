#!/bin/bash
# Export result for add_provider_specialty task

echo "=== Exporting add_provider_specialty result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_specialty_end.png

# Query the database to find any records matching the expected data.
# Since EMRs dynamically generate schema for support data modules,
# we use a heuristic search across all tables.

echo "Scanning database for taxonomy code and specialty name..."

python3 -c "
import mysql.connector
import json
import datetime

def serialize_datetime(obj):
    if isinstance(obj, (datetime.date, datetime.datetime)):
        return obj.isoformat()
    if isinstance(obj, bytes):
        try:
            return obj.decode('utf-8')
        except:
            return str(obj)
    return obj

result = {
    'records_found': [],
    'db_scanned': False,
    'error': None
}

try:
    db = mysql.connector.connect(user='freemed', password='freemed', database='freemed', host='localhost')
    cursor = db.cursor()
    cursor.execute('SHOW TABLES')
    tables = [t[0] for t in cursor.fetchall()]
    
    for table in tables:
        try:
            cursor.execute(f'SHOW COLUMNS FROM \`{table}\`')
            cols = [c[0] for c in cursor.fetchall()]
            
            cursor.execute(f'SELECT * FROM \`{table}\`')
            for row in cursor.fetchall():
                row_dict = dict(zip(cols, row))
                
                # Create a searchable string of all values in the row
                row_str = ' '.join([str(v) for v in row if v is not None]).lower()
                
                # Check if this row contains our target data
                has_taxonomy = '207rg0100x' in row_str
                has_specialty = 'gastroenterology' in row_str
                has_description = 'digestive' in row_str or 'specialist' in row_str
                
                if has_taxonomy or has_specialty:
                    # Clean the dict for JSON serialization
                    clean_dict = {k: serialize_datetime(v) for k, v in row_dict.items()}
                    
                    result['records_found'].append({
                        'table': table,
                        'data': clean_dict,
                        'has_taxonomy': has_taxonomy,
                        'has_specialty': has_specialty,
                        'has_description': has_description,
                        'raw_string': row_str
                    })
        except Exception as e:
            continue
            
    result['db_scanned'] = True
except Exception as e:
    result['error'] = str(e)

# Write to temp file safely
import tempfile
import os
import shutil

fd, path = tempfile.mkstemp(suffix='.json')
with os.fdopen(fd, 'w') as f:
    json.dump(result, f)

# Copy to final location
os.system(f'cp {path} /tmp/add_provider_specialty_result.json')
os.system('chmod 666 /tmp/add_provider_specialty_result.json 2>/dev/null || sudo chmod 666 /tmp/add_provider_specialty_result.json')
os.unlink(path)
print('Database scan complete. Results saved to /tmp/add_provider_specialty_result.json')
"

echo "=== Export Complete ==="