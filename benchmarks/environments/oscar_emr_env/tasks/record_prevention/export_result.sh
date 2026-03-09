#!/bin/bash
set -e
echo "=== Exporting record_prevention results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Parameters
PATIENT_ID=$(cat /tmp/maria_santos_demo_no.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_flu_count.txt 2>/dev/null || echo "0")

# Use Python to extract structured data from DB
# This handles the complexity of joining preventions and preventionsExt cleanly
python3 -c "
import pymysql
import json
import time
import os

try:
    conn = pymysql.connect(
        host='oscar-db',
        user='oscar',
        password='oscar',
        database='oscar',
        cursorclass=pymysql.cursors.DictCursor
    )
    
    with conn.cursor() as cursor:
        # Get patient info
        cursor.execute('SELECT * FROM demographic WHERE demographic_no=%s', ($PATIENT_ID,))
        patient = cursor.fetchone()
        
        # Get latest Flu prevention for this patient
        cursor.execute('''
            SELECT * FROM preventions 
            WHERE demographic_no=%s 
            AND prevention_type="Flu" 
            AND (deleted IS NULL OR deleted != 1)
            ORDER BY id DESC LIMIT 1
        ''', ($PATIENT_ID,))
        prevention = cursor.fetchone()
        
        result = {
            'task_start_ts': $TASK_START,
            'initial_count': $INITIAL_COUNT,
            'patient_found': bool(patient),
            'prevention_found': False,
            'record': None,
            'ext_data': {}
        }
        
        if prevention:
            # Get extended data (key-value pairs)
            cursor.execute('SELECT keyval, val FROM preventionsExt WHERE prevention_id=%s', (prevention['id'],))
            ext_rows = cursor.fetchall()
            ext_data = {row['keyval']: row['val'] for row in ext_rows}
            
            # Convert dates to string
            if prevention.get('prevention_date'):
                prevention['prevention_date'] = str(prevention['prevention_date'])
            if prevention.get('creation_date'):
                prevention['creation_date_ts'] = prevention['creation_date'].timestamp()
                prevention['creation_date'] = str(prevention['creation_date'])
            
            result['prevention_found'] = True
            result['record'] = prevention
            result['ext_data'] = ext_data
            
            # Get current count
            cursor.execute('SELECT COUNT(*) as cnt FROM preventions WHERE demographic_no=%s AND prevention_type=\"Flu\" AND (deleted IS NULL OR deleted != 1)', ($PATIENT_ID,))
            cnt = cursor.fetchone()
            result['current_count'] = cnt['cnt']

    print(json.dumps(result, indent=2))
    
    # Save to file
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)

finally:
    if 'conn' in locals() and conn.open:
        conn.close()
" > /tmp/db_export_output.txt 2>&1

# Check if python script failed
if [ ! -f /tmp/task_result.json ]; then
    echo "ERROR: Python export failed"
    cat /tmp/db_export_output.txt
    # Create fallback failure json
    echo '{"error": "Export failed"}' > /tmp/task_result.json
fi

# Set permissions
chmod 666 /tmp/task_result.json
echo "Export saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="