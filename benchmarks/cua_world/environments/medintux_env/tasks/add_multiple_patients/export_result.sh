#!/bin/bash
echo "=== Exporting add_multiple_patients results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the database for all MOREAU patients created
# We output as tab-separated values to parse into JSON
echo "Querying database for MOREAU patients..."

# Create a Python script to fetch data and format as JSON
# This is more robust than bash parsing for potential special characters
cat > /tmp/fetch_results.py << 'PYEOF'
import pymysql
import json
import time

try:
    conn = pymysql.connect(
        host='localhost',
        user='root',
        password='',
        database='DrTuxTest',
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )
    
    with conn.cursor() as cursor:
        # Fetch join of Index and Details
        sql = """
        SELECT 
            i.FchGnrl_IDDos as guid,
            i.FchGnrl_NomDos as nom,
            i.FchGnrl_Prenom as prenom,
            f.FchPat_Nee as dob,
            f.FchPat_Sexe as sexe,
            f.FchPat_Adresse as adresse,
            f.FchPat_CP as cp,
            f.FchPat_Ville as ville,
            f.FchPat_NumSS as numss
        FROM IndexNomPrenom i
        LEFT JOIN fchpat f ON i.FchGnrl_IDDos = f.FchPat_GUID_Doss
        WHERE i.FchGnrl_NomDos = 'MOREAU'
          AND i.FchGnrl_Type = 'Dossier'
        """
        cursor.execute(sql)
        results = cursor.fetchall()
        
        # Format dates to string
        for row in results:
            if row['dob']:
                row['dob'] = str(row['dob'])
                
    print(json.dumps(results))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
finally:
    if 'conn' in locals() and conn.open:
        conn.close()
PYEOF

# Execute the python script
PATIENT_DATA=$(python3 /tmp/fetch_results.py)

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_total_patient_count.txt 2>/dev/null || echo 0)
CURRENT_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || echo 0)

# Build final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "patients_found": $PATIENT_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json