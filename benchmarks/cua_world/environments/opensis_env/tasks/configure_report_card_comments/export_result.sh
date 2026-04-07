#!/bin/bash
echo "=== Exporting task results ==="

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query the database for the specific comments created
# We look for codes PLE and MHW specifically
echo "Querying database..."

# Use python to robustly query and export to JSON
python3 -c "
import mysql.connector
import json
import os
import time

try:
    conn = mysql.connector.connect(
        user='$DB_USER',
        password='$DB_PASS',
        host='localhost',
        database='$DB_NAME'
    )
    cursor = conn.cursor(dictionary=True)
    
    # Query for our target comments
    query = \"SELECT title, code, sort_order, school_id, syear FROM report_card_comments WHERE code IN ('PLE', 'MHW') AND school_id=1\"
    cursor.execute(query)
    rows = cursor.fetchall()
    
    # Get total count for sanity check
    cursor.execute(\"SELECT COUNT(*) as total FROM report_card_comments WHERE school_id=1\")
    total_count = cursor.fetchone()['total']
    
    result = {
        'found_comments': rows,
        'total_comments_count': total_count,
        'query_success': True,
        'timestamp': time.time()
    }
    
    conn.close()
    
except Exception as e:
    result = {
        'found_comments': [],
        'query_success': False,
        'error': str(e)
    }

# Write to temp file first
with open('/tmp/result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to final location safely
mv /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="