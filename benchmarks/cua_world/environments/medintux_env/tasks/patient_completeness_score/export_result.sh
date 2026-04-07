#!/bin/bash
echo "=== Exporting patient_completeness_score results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/patient_completeness_report.csv"

# 1. Check Output File
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 2. Export Actual Database State to JSON for Verifier
# We write a python script to query MySQL and dump the ground truth
# This ensures the verifier compares against the actual data in the DB
cat > /tmp/export_db_state.py << 'PYEOF'
import pymysql
import json
import sys

try:
    conn = pymysql.connect(
        host='localhost',
        user='root',
        password='',
        db='DrTuxTest',
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )
    
    with conn.cursor() as cursor:
        # Query matching the task requirements
        # Join IndexNomPrenom and fchpat
        sql = """
        SELECT 
            f.FchPat_GUID_Doss as guid,
            i.FchGnrl_NomDos as nom,
            i.FchGnrl_Prenom as prenom,
            f.FchPat_NomFille,
            f.FchPat_Nee,
            f.FchPat_Sexe,
            f.FchPat_Titre,
            f.FchPat_Adresse,
            f.FchPat_CP,
            f.FchPat_Ville,
            f.FchPat_Tel1,
            f.FchPat_NumSS
        FROM fchpat f
        JOIN IndexNomPrenom i ON f.FchPat_GUID_Doss = i.FchGnrl_IDDos
        """
        cursor.execute(sql)
        rows = cursor.fetchall()
        
        # Convert date objects to strings if needed
        for row in rows:
            for k, v in row.items():
                if hasattr(v, 'isoformat'):
                    row[k] = v.isoformat()
        
        with open('/tmp/db_ground_truth.json', 'w') as f:
            json.dump(rows, f)
            
except Exception as e:
    print(f"Error exporting DB: {e}", file=sys.stderr)
finally:
    if 'conn' in locals():
        conn.close()
PYEOF

python3 /tmp/export_db_state.py

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "db_dump_path": "/tmp/db_ground_truth.json",
    "csv_path": "$OUTPUT_PATH"
}
EOF

# Move result to expected location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="