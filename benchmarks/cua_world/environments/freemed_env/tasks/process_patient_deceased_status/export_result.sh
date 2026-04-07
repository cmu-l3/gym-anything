#!/bin/bash
echo "=== Exporting process_patient_deceased_status result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a Python script to safely extract the DB record to JSON
cat > /tmp/export_db_record.py << 'PYEOF'
import json
import datetime
import sys
import subprocess

# Ensure mysql-connector is available
try:
    import mysql.connector
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "mysql-connector-python"])
    import mysql.connector

try:
    conn = mysql.connector.connect(user='freemed', password='freemed', host='localhost', database='freemed')
    cursor = conn.cursor(dictionary=True)
    
    # Fetch Arthur Pendelton's record
    cursor.execute("SELECT * FROM patient WHERE ptfname='Arthur' AND ptlname='Pendelton' LIMIT 1")
    row = cursor.fetchone()
    
    # Handle datetime serialization
    if row:
        for k, v in row.items():
            if isinstance(v, (datetime.date, datetime.datetime)):
                row[k] = v.isoformat()
                
    result = {
        'patient_found': bool(row),
        'patient': row if row else {}
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    print(f"Successfully exported patient record to JSON (Found: {bool(row)})")

except Exception as e:
    print(f"Error extracting database record: {e}")
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'patient_found': False, 'error': str(e)}, f)
PYEOF

# Run the Python export script
python3 /tmp/export_db_record.py

# Display the exported JSON for debugging
if [ -f /tmp/task_result.json ]; then
    cat /tmp/task_result.json
else
    echo '{"patient_found": false, "error": "Export file not created"}' > /tmp/task_result.json
fi

# Set permissions so the host verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="