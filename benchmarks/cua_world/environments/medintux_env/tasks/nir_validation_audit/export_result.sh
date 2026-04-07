#!/bin/bash
echo "=== Exporting NIR Validation Audit Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check report file
REPORT_PATH="/home/ga/nir_audit_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Get current patient count (anti-gaming: check if agent deleted patients)
CURRENT_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_patient_count.txt 2>/dev/null || echo "0")

# Dump current test patient data for verifier (to check if DB was altered)
# We dump just the names and NIRs of our test subjects
TEST_PATIENTS_STATE=$(mysql -u root DrTuxTest -N -e "SELECT FchPat_NomFille, FchPat_NumSS FROM fchpat WHERE FchPat_NomFille IN ('AUBERT','BEAUMONT','CHEVALIER','DUFOUR','FABRE','GARNIER','HUBERT','JOUBERT')" 2>/dev/null)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size": $REPORT_SIZE,
    "initial_db_count": $INITIAL_COUNT,
    "current_db_count": $CURRENT_COUNT,
    "screenshot_path": "/tmp/task_final.png",
    "db_integrity_check": $(echo "$TEST_PATIENTS_STATE" | jq -R -s -c '.')
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="