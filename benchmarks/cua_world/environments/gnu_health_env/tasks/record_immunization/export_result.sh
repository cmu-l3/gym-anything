#!/bin/bash
echo "=== Exporting record_immunization result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Execute a Python script to safely query the database and generate JSON
cat > /tmp/export_data.py << 'PYEOF'
import json
import os
import sys

# Locate site-packages for trytond/psycopg2
import glob
site_packages = glob.glob('/opt/gnuhealth/venv/lib/python3.*/site-packages')
if site_packages:
    sys.path.insert(0, site_packages[0])

try:
    import psycopg2
except ImportError:
    print('{"error": "psycopg2 not found"}')
    sys.exit(1)

# Read baseline max ID
try:
    with open('/tmp/baseline_vaccination_max', 'r') as f:
        baseline_max = int(f.read().strip())
except:
    baseline_max = 0

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# Connect to database
try:
    conn = psycopg2.connect(dbname='health50', user='gnuhealth')
    cur = conn.cursor()
    
    # Query for the latest vaccination record added after the baseline
    query = """
    SELECT 
        gv.id, 
        pp.name as first_name, 
        pp.lastname as last_name, 
        tmpl.name as vaccine_name, 
        gv.date, 
        gv.dose, 
        gv.observations
    FROM gnuhealth_vaccination gv
    JOIN gnuhealth_patient gp ON gv.name = gp.id
    JOIN party_party pp ON gp.party = pp.id
    LEFT JOIN gnuhealth_medicament gm ON gv.vaccine = gm.id
    LEFT JOIN product_product prod ON gm.name = prod.id
    LEFT JOIN product_template tmpl ON prod.template = tmpl.id
    WHERE gv.id > %s
    ORDER BY gv.id DESC LIMIT 1
    """
    cur.execute(query, (baseline_max,))
    row = cur.fetchone()
    
    result = {
        "new_record_found": False,
        "task_start_time": task_start,
        "baseline_max": baseline_max,
        "record": None
    }
    
    if row:
        result["new_record_found"] = True
        result["record"] = {
            "id": row[0],
            "patient_name": row[1] or "",
            "patient_lastname": row[2] or "",
            "vaccine_name": row[3] or "",
            "date": str(row[4]) if row[4] else "",
            "dose": row[5] if row[5] is not None else -1,
            "observations": row[6] or ""
        }
        
    # Check total new records created
    cur.execute("SELECT COUNT(*) FROM gnuhealth_vaccination WHERE id > %s", (baseline_max,))
    result["total_new_records"] = cur.fetchone()[0]

    cur.close()
    conn.close()

    with open('/tmp/record_immunization_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    with open('/tmp/record_immunization_result.json', 'w') as f:
        json.dump({"error": str(e), "new_record_found": False}, f)

PYEOF

# Run the python script as the gnuhealth user
sudo -u gnuhealth /opt/gnuhealth/venv/bin/python3 /tmp/export_data.py

# Ensure permissions
chmod 666 /tmp/record_immunization_result.json 2>/dev/null || true

echo "Export completed:"
cat /tmp/record_immunization_result.json

echo "=== Export Complete ==="