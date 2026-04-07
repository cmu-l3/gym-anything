#!/bin/bash
echo "=== Exporting Drug-Diagnosis Crossref Result ==="

# Define paths
REPORT_PATH="/home/ga/drug_diagnosis_crossref_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_SIZE="0"
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Encode content for safe transport (limit to 100KB)
    REPORT_CONTENT_B64=$(head -c 100000 "$REPORT_PATH" | base64 -w 0)
fi

# 2. Generate Ground Truth Data (Run queries inside container to verify agent's work)
# We need to know the table names. Based on MedinTux standard schema:
# MedicaTuxTest -> Table 'SP' or 'Sp_Specialites' usually has 'Code_ATC'
# CIM10Test -> Table 'CIM10' or 'Libelles'

echo "Generating ground truth..."

# Helper to find table names if they vary
DRUG_TABLE=$(mysql -u root -N -e "SELECT TABLE_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='MedicaTuxTest' AND COLUMN_NAME LIKE '%ATC%' LIMIT 1" 2>/dev/null)
ATC_COL=$(mysql -u root -N -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='MedicaTuxTest' AND TABLE_NAME='$DRUG_TABLE' AND COLUMN_NAME LIKE '%ATC%' LIMIT 1" 2>/dev/null)

CIM_TABLE=$(mysql -u root -N -e "SELECT TABLE_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='CIM10Test' AND COLUMN_NAME LIKE '%Code%' LIMIT 1" 2>/dev/null)
CIM_COL=$(mysql -u root -N -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='CIM10Test' AND TABLE_NAME='$CIM_TABLE' AND COLUMN_NAME LIKE '%Code%' LIMIT 1" 2>/dev/null)

GT_ATC_COUNTS="[]"
if [ -n "$DRUG_TABLE" ] && [ -n "$ATC_COL" ]; then
    # Count drugs by first letter of ATC code
    GT_ATC_COUNTS=$(mysql -u root MedicaTuxTest -e "SELECT LEFT($ATC_COL, 1) as Code, COUNT(*) as Count FROM $DRUG_TABLE GROUP BY LEFT($ATC_COL, 1) ORDER BY Code" -N 2>/dev/null | \
    python3 -c "import sys, json; print(json.dumps([{'code': line.split()[0], 'count': int(line.split()[1])} for line in sys.stdin if line.strip()]))")
fi

GT_CIM_COUNTS="[]"
if [ -n "$CIM_TABLE" ] && [ -n "$CIM_COL" ]; then
    # Count diagnoses by first letter (rough chapter approximation for verification)
    GT_CIM_COUNTS=$(mysql -u root CIM10Test -e "SELECT LEFT($CIM_COL, 1) as Code, COUNT(*) as Count FROM $CIM_TABLE GROUP BY LEFT($CIM_COL, 1) ORDER BY Code" -N 2>/dev/null | \
    python3 -c "import sys, json; print(json.dumps([{'code': line.split()[0], 'count': int(line.split()[1])} for line in sys.stdin if line.strip()]))")
fi

# 3. Check Bash History for Process Evidence
# Check if user ran mysql commands
HISTORY_EVIDENCE="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "mysql" /home/ga/.bash_history; then
        HISTORY_EVIDENCE="true"
    fi
fi
# Also check if mysql process ran recently
if ps -eo comm,etime | grep -q "mysql"; then
    HISTORY_EVIDENCE="true"
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT_B64",
    "ground_truth": {
        "atc_counts": $GT_ATC_COUNTS,
        "cim_counts": $GT_CIM_COUNTS,
        "drug_table_found": "$DRUG_TABLE",
        "cim_table_found": "$CIM_TABLE"
    },
    "process_evidence": $HISTORY_EVIDENCE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"