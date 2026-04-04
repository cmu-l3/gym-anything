#!/bin/bash
set -e
echo "=== Exporting Triage Security Incident Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from Database
# We need to export:
# - The Incident record (to check values)
# - The ID for 'Denial of Service' (to compare with incident.classification_id)
# - The ID for 'admin' (to compare with incident.owner_id)
# - The ID for 'High' severity (if possible, or just the raw value)

echo "Querying database state..."

# Helper to run SQL and output JSON
# We construct a complex JSON object using python inside the container or by careful shell scripting
# Here we use a python script to query DB and dump JSON to ensure type safety and handle NULLs
cat > /tmp/dump_result.py << 'EOF'
import pymysql
import json
import os
import sys

def get_db_connection():
    return pymysql.connect(
        host='127.0.0.1',
        user='eramba',
        password='eramba_db_pass',
        db='eramba',
        cursorclass=pymysql.cursors.DictCursor
    )

result = {}

try:
    conn = get_db_connection()
    with conn.cursor() as cursor:
        # 1. Fetch the Incident
        cursor.execute("SELECT * FROM security_incidents WHERE title='SIEM Alert: High Volume Traffic'")
        incident = cursor.fetchone()
        
        # 2. Fetch Classification ID
        cursor.execute("SELECT id FROM taxonomy_lookups WHERE name='Denial of Service' AND model='SecurityIncident'")
        class_row = cursor.fetchone()
        
        # 3. Fetch Admin ID
        cursor.execute("SELECT id FROM users WHERE login='admin'")
        user_row = cursor.fetchone()
        
        # 4. Fetch Severity IDs (Lookup table often named 'transposed_terms' or similar in some versions, 
        # or it's a hardcoded dropdown. We will check the raw value in incident first.
        # If incident.severity_id is used, we look that up.)
        
        result['incident'] = incident if incident else None
        result['expected_class_id'] = class_row['id'] if class_row else None
        result['expected_owner_id'] = user_row['id'] if user_row else 1
        
        # Add timestamps for serialization
        if incident and 'modified' in incident:
            result['incident']['modified_ts'] = incident['modified'].timestamp()
            del incident['modified'] # Remove datetime obj
        if incident and 'created' in incident:
            del incident['created']

except Exception as e:
    result['error'] = str(e)
finally:
    if 'conn' in locals() and conn:
        conn.close()

print(json.dumps(result))
EOF

# Copy script to db container and execute (or execute from app container if it has python+pymysql)
# Since we need python with pymysql, let's try running it locally if pymysql is installed, 
# or use docker exec with simple mysql queries if python fails.
# The environment has python3, but maybe not pymysql. 
# Plan B: Bash + mysql client formatted output.

# Using docker exec mysql with specific formatting
echo "Exporting via MySQL client..."

# Get Incident Data
INCIDENT_JSON=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT JSON_OBJECT(
        'classification_id', classification_id,
        'severity_id', severity_id,
        'owner_id', owner_id,
        'modified', UNIX_TIMESTAMP(modified)
    ) FROM security_incidents WHERE title='SIEM Alert: High Volume Traffic';" 2>/dev/null || echo "{}")

# Get Expected IDs
CLASS_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id FROM taxonomy_lookups WHERE name='Denial of Service' AND model='SecurityIncident' LIMIT 1;" 2>/dev/null || echo "0")

ADMIN_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id FROM users WHERE login='admin' LIMIT 1;" 2>/dev/null || echo "1")

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Construct Final JSON
cat > /tmp/task_result.json << JSON
{
    "incident": $INCIDENT_JSON,
    "expected_class_id": $CLASS_ID,
    "expected_owner_id": $ADMIN_ID,
    "task_start_time": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
JSON

echo "Result JSON created at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="