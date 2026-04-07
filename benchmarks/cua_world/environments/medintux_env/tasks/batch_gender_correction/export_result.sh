#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the specific test GUIDs and export to JSON
# We use Python here to generate clean JSON from MySQL query
python3 -c "
import pymysql
import json
import time

try:
    conn = pymysql.connect(host='localhost', user='root', password='', database='DrTuxTest', charset='utf8mb4', cursorclass=pymysql.cursors.DictCursor)
    
    # Define the GUIDs we care about (must match setup_task.sh)
    target_guids = ['GUID_T1', 'GUID_T2', 'GUID_T3', 'GUID_T4']
    distractor_guids = ['GUID_D1', 'GUID_D2', 'GUID_D3']
    baseline_guids = ['GUID_B1', 'GUID_B2']
    all_guids = target_guids + distractor_guids + baseline_guids
    
    format_strings = ','.join(['%s'] * len(all_guids))
    
    with conn.cursor() as cursor:
        sql = f'SELECT FchPat_GUID_Doss, FchPat_Sexe FROM fchpat WHERE FchPat_GUID_Doss IN ({format_strings})'
        cursor.execute(sql, all_guids)
        rows = cursor.fetchall()
        
    # Convert list of dicts to a dict keyed by GUID for easier verification
    results = {row['FchPat_GUID_Doss']: row['FchPat_Sexe'] for row in rows}
    
    # Count total 'F' records to check for massive over-correction
    with conn.cursor() as cursor:
        cursor.execute(\"SELECT COUNT(*) as count FROM fchpat WHERE FchPat_Sexe = 'F'\")
        total_female = cursor.fetchone()['count']
        
    output = {
        'records': results,
        'total_female_count': total_female,
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'timestamp': time.time()
    }
    
    print(json.dumps(output, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))
finally:
    if 'conn' in locals() and conn.open:
        conn.close()
" > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="