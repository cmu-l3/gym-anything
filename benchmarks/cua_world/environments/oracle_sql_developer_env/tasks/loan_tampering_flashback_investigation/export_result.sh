#!/bin/bash
echo "=== Exporting Loan Tampering Flashback Investigation Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 1. Fetch current values of the 7 target loans
echo "Fetching current loan values..."
CURRENT_LOANS_CSV=$(oracle_query_raw "
SELECT loan_id || ',' || interest_rate || ',' || current_balance || ',' || status
FROM lending_admin.loan_accounts 
WHERE loan_id IN (1005, 1012, 1023, 1034, 1041, 1045, 1049);
" "system")

# Convert CSV output to a JSON structure using python
CURRENT_LOANS_JSON=$(python3 -c "
import json
import sys
loans = {}
for line in sys.stdin:
    parts = line.strip().split(',')
    if len(parts) == 4:
        try:
            lid = parts[0]
            loans[lid] = {
                'interest_rate': float(parts[1]),
                'current_balance': float(parts[2]),
                'status': parts[3]
            }
        except:
            pass
print(json.dumps(loans))
" <<< "$CURRENT_LOANS_CSV")

# 2. Check INVESTIGATION_FINDINGS table
FINDINGS_EXISTS=false
FINDINGS_ROWS=0
FINDINGS_TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'LENDING_ADMIN' AND table_name = 'INVESTIGATION_FINDINGS';" "system" | tr -d '[:space:]')
if [ "${FINDINGS_TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FINDINGS_EXISTS=true
    FINDINGS_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM lending_admin.investigation_findings;" "system" | tr -d '[:space:]')
fi

# 3. Check AUDIT table and trigger
AUDIT_TBL_EXISTS=false
AUDIT_TRIGGER_EXISTS=false
AUDIT_TRIGGER_FIRED=false

TBL_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'LENDING_ADMIN' AND table_name = 'LOAN_CHANGE_AUDIT';" "system" | tr -d '[:space:]')
if [ "${TBL_CHK:-0}" -gt 0 ] 2>/dev/null; then
    AUDIT_TBL_EXISTS=true
fi

TRG_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_triggers WHERE owner = 'LENDING_ADMIN' AND trigger_name = 'TRG_LOAN_AUDIT' AND table_name = 'LOAN_ACCOUNTS' AND status = 'ENABLED';" "system" | tr -d '[:space:]')
if [ "${TRG_CHK:-0}" -gt 0 ] 2>/dev/null; then
    AUDIT_TRIGGER_EXISTS=true
fi

# Test the trigger by updating a non-tampered loan
if [ "$AUDIT_TBL_EXISTS" = "true" ] && [ "$AUDIT_TRIGGER_EXISTS" = "true" ]; then
    oracle_query "UPDATE lending_admin.loan_accounts SET interest_rate = 9.99 WHERE loan_id = 1001; COMMIT; EXIT;" "lending_admin" "Lending2024" > /dev/null 2>&1
    
    FIRE_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM lending_admin.loan_change_audit WHERE loan_id = 1001 AND new_value = '9.99';" "system" | tr -d '[:space:]')
    if [ "${FIRE_CHK:-0}" -gt 0 ] 2>/dev/null; then
        AUDIT_TRIGGER_FIRED=true
    fi
fi

# 4. Check CSV Export
CSV_EXISTS=false
CSV_SIZE=0
if [ -f "/home/ga/Documents/exports/investigation_report.csv" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "/home/ga/Documents/exports/investigation_report.csv" 2>/dev/null || echo "0")
fi

# 5. Collect GUI Evidence & Flashback keywords in SQL History
GUI_EVIDENCE=$(collect_gui_evidence)

FLASHBACK_USED=false
if [ -d "/home/ga/.sqldeveloper/SqlHistory" ]; then
    if grep -qiE "VERSIONS\s+BETWEEN|AS\s+OF\s+SCN" /home/ga/.sqldeveloper/SqlHistory/*.xml 2>/dev/null; then
        FLASHBACK_USED=true
    fi
fi

# Look for flashback in v$sql as fallback
if [ "$FLASHBACK_USED" = "false" ]; then
    VSQL_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM v\$sql WHERE (UPPER(sql_text) LIKE '%VERSIONS BETWEEN%' OR UPPER(sql_text) LIKE '%AS OF SCN%') AND parsing_schema_name = 'LENDING_ADMIN';" "system" | tr -d '[:space:]')
    if [ "${VSQL_CHK:-0}" -gt 0 ] 2>/dev/null; then
        FLASHBACK_USED=true
    fi
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "findings_table_exists": $FINDINGS_EXISTS,
    "findings_row_count": ${FINDINGS_ROWS:-0},
    "audit_table_exists": $AUDIT_TBL_EXISTS,
    "audit_trigger_exists": $AUDIT_TRIGGER_EXISTS,
    "audit_trigger_fired": $AUDIT_TRIGGER_FIRED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "flashback_used": $FLASHBACK_USED,
    "current_loans": $CURRENT_LOANS_JSON,
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/loan_tampering_result.json 2>/dev/null || sudo rm -f /tmp/loan_tampering_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/loan_tampering_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/loan_tampering_result.json
chmod 666 /tmp/loan_tampering_result.json 2>/dev/null || sudo chmod 666 /tmp/loan_tampering_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/loan_tampering_result.json"
echo "=== Export Complete ==="