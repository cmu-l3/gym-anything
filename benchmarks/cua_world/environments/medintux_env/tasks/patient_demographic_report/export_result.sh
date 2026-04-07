#!/bin/bash
echo "=== Exporting Patient Demographics Report Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/patient_demographics_report.txt"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. CHECK REPORT FILE
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content (base64 to avoid JSON escaping issues, or just read text)
    # We will read it as text for the Python script to generate JSON
    REPORT_CONTENT=$(cat "$REPORT_PATH")
fi

# 2. GENERATE GROUND TRUTH FROM DATABASE
# We use Python to calculate precise ages based on CURRENT date inside the container
# and query the DB for the ground truth values.

cat > /tmp/calculate_ground_truth.py << 'PYEOF'
import json
import pymysql
import datetime
import sys

# Current date
today = datetime.date.today()

def calculate_age(born):
    if not born: return 0
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))

try:
    conn = pymysql.connect(host='localhost', user='root', password='', db='DrTuxTest', charset='utf8mb4')
    cursor = conn.cursor(pymysql.cursors.DictCursor)
    
    # Get all patients
    cursor.execute("SELECT FchPat_NomFille as Nom, FchPat_Nee as DOB, FchPat_Sexe as Sexe FROM fchpat")
    patients = cursor.fetchall()
    
    total = len(patients)
    males = 0
    females = 0
    total_age = 0
    oldest_age = -1
    youngest_age = 999
    oldest_name = ""
    youngest_name = ""
    
    patient_list = []
    
    for p in patients:
        dob_str = str(p['DOB'])
        dob_date = datetime.datetime.strptime(dob_str, "%Y-%m-%d").date()
        age = calculate_age(dob_date)
        
        sex = p['Sexe'].upper() # M or F
        if sex == 'M' or sex == 'H':
            males += 1
        else:
            females += 1
            
        total_age += age
        
        if age > oldest_age:
            oldest_age = age
            oldest_name = f"{p['Nom']} (born {dob_str})"
        
        if age < youngest_age:
            youngest_age = age
            youngest_name = f"{p['Nom']} (born {dob_str})"
            
        patient_list.append({
            "name": p['Nom'],
            "dob": dob_str,
            "sex": sex,
            "age": age
        })
            
    avg_age = round(total_age / total) if total > 0 else 0
    
    ground_truth = {
        "total": total,
        "males": males,
        "females": females,
        "average_age": avg_age,
        "oldest_str": oldest_name,
        "youngest_str": youngest_name,
        "patients": patient_list
    }
    
    print(json.dumps(ground_truth))

except Exception as e:
    print(json.dumps({"error": str(e)}))
finally:
    if 'conn' in locals() and conn.open: conn.close()
PYEOF

GROUND_TRUTH_JSON=$(python3 /tmp/calculate_ground_truth.py)

# 3. CREATE FINAL RESULT JSON
# Use Python to safely combine everything into valid JSON
cat > /tmp/create_result.py << PYEOF
import json
import os
import time

try:
    report_exists = "$REPORT_EXISTS" == "true"
    report_created_during = "$REPORT_CREATED_DURING_TASK" == "true"
    
    report_content = ""
    if report_exists:
        try:
            with open("$REPORT_PATH", 'r', encoding='utf-8') as f:
                report_content = f.read()
        except:
            report_content = ""

    ground_truth = json.loads('''$GROUND_TRUTH_JSON''')
    
    result = {
        "report_exists": report_exists,
        "report_created_during_task": report_created_during,
        "report_content": report_content,
        "ground_truth": ground_truth,
        "task_start": $TASK_START,
        "task_end": int(time.time())
    }
    
    with open("$RESULT_JSON", 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    with open("$RESULT_JSON", 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

python3 /tmp/create_result.py

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="