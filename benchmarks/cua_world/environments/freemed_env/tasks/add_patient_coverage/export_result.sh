#!/bin/bash
# Export script for add_patient_coverage task

echo "=== Exporting add_patient_coverage Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_coverage_end.png
sleep 1

echo "Extracting coverage data from database..."

# Use a Python script to robustly extract database records into JSON
# This avoids issues with changing column names or MySQL formatting
cat > /tmp/extract_coverage.py << 'EOF'
import pymysql
import json
from datetime import date, datetime

def default_converter(o):
    if isinstance(o, (datetime, date)):
        return o.isoformat()
    return str(o)

try:
    conn = pymysql.connect(
        host='localhost', 
        user='freemed', 
        password='freemed', 
        database='freemed', 
        cursorclass=pymysql.cursors.DictCursor
    )
    result = {
        "success": True,
        "patient_id": None,
        "insco_id": None,
        "coverages": []
    }
    
    with conn.cursor() as cursor:
        # Get Patient ID
        cursor.execute("SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1")
        patient = cursor.fetchone()
        if patient:
            result['patient_id'] = patient['id']
            
        # Get Insco ID
        cursor.execute("SELECT id FROM insco WHERE insconame='BlueCross BlueShield' LIMIT 1")
        insco = cursor.fetchone()
        if insco:
            result['insco_id'] = insco['id']
            
        # Get Coverages for Patient
        if result['patient_id']:
            # Using generic SELECT * to capture any schema variations for coverage
            cursor.execute("SELECT * FROM coverage WHERE patient=%s ORDER BY id DESC", (result['patient_id'],))
            result['coverages'] = cursor.fetchall()
            
except Exception as e:
    result = {"success": False, "error": str(e)}

with open('/tmp/add_patient_coverage_result.json', 'w') as f:
    json.dump(result, f, default=default_converter, indent=2)
EOF

# Run the extraction script
python3 /tmp/extract_coverage.py

# Ensure permissions allow verifier to read it
chmod 666 /tmp/add_patient_coverage_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/add_patient_coverage_result.json"
cat /tmp/add_patient_coverage_result.json

echo ""
echo "=== Export Complete ==="