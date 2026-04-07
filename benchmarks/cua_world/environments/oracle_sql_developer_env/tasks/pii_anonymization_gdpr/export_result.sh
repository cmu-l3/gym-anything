#!/bin/bash
echo "=== Exporting PII Anonymization Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize vars
PKG_EXISTS=false
PKG_VALID=false
FUNC_COUNT=0
DETERMINISTIC_NAME=false
EMAIL_MASKED=false
PHONE_MASKED=false
IBAN_MASKED=false
CUSTOMERS_VW_EXISTS=false
TRANS_VW_EXISTS=false
TICKETS_VW_EXISTS=false
PII_SCAN_TBL_EXISTS=false
PII_SCAN_ROWS=0
SCAN_FOUND_EMAIL=false
LOG_TBL_EXISTS=false
LOG_ROWS=0
TICKETS_REDACTED=false
CSV_EXISTS=false
CSV_SIZE=0

# 1. Check Package
PKG_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner='GDPR_ADMIN' AND object_name='DATA_ANONYMIZER_PKG' AND object_type='PACKAGE';" "system" | tr -d '[:space:]')
if [ "${PKG_CHK:-0}" -gt 0 ] 2>/dev/null; then
    PKG_EXISTS=true
fi

PKG_VAL_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner='GDPR_ADMIN' AND object_name='DATA_ANONYMIZER_PKG' AND object_type='PACKAGE BODY' AND status='VALID';" "system" | tr -d '[:space:]')
if [ "${PKG_VAL_CHK:-0}" -gt 0 ] 2>/dev/null; then
    PKG_VALID=true
fi

# 2. Check Functions
FUNC_COUNT=$(oracle_query_raw "SELECT COUNT(DISTINCT procedure_name) FROM all_procedures WHERE owner='GDPR_ADMIN' AND object_name='DATA_ANONYMIZER_PKG' AND procedure_name IN ('MASK_NAME', 'MASK_EMAIL', 'MASK_PHONE', 'MASK_IBAN', 'GENERALIZE_ADDRESS', 'SHIFT_DATE');" "system" | tr -d '[:space:]')
FUNC_COUNT=${FUNC_COUNT:-0}

# Test Determinism and Outputs (if valid)
if [ "$PKG_VALID" = "true" ]; then
    NAME1=$(oracle_query_raw "SELECT gdpr_admin.data_anonymizer_pkg.mask_name('Alice') FROM dual;" "system" 2>/dev/null)
    NAME2=$(oracle_query_raw "SELECT gdpr_admin.data_anonymizer_pkg.mask_name('Alice') FROM dual;" "system" 2>/dev/null)
    
    if [ -n "$NAME1" ] && [ "$NAME1" != "ERROR" ] && [ "$NAME1" = "$NAME2" ]; then
        if echo "$NAME1" | grep -q "ANON_"; then
            DETERMINISTIC_NAME=true
        fi
    fi
    
    EMAIL1=$(oracle_query_raw "SELECT gdpr_admin.data_anonymizer_pkg.mask_email('john.doe@example.com') FROM dual;" "system" 2>/dev/null)
    if [ -n "$EMAIL1" ] && [ "$EMAIL1" != "ERROR" ] && echo "$EMAIL1" | grep -q "@example.com" && ! echo "$EMAIL1" | grep -q "john.doe"; then
        EMAIL_MASKED=true
    fi
    
    PHONE1=$(oracle_query_raw "SELECT gdpr_admin.data_anonymizer_pkg.mask_phone('+49 30 1234') FROM dual;" "system" 2>/dev/null)
    if [ -n "$PHONE1" ] && [ "$PHONE1" != "ERROR" ] && echo "$PHONE1" | grep -q "+49" && echo "$PHONE1" | grep -q "\*"; then
        PHONE_MASKED=true
    fi
    
    IBAN1=$(oracle_query_raw "SELECT gdpr_admin.data_anonymizer_pkg.mask_iban('DE89370400440532013000') FROM dual;" "system" 2>/dev/null)
    if [ -n "$IBAN1" ] && [ "$IBAN1" != "ERROR" ] && echo "$IBAN1" | grep -q "DE89" && echo "$IBAN1" | grep -q "3000" && echo "$IBAN1" | grep -q "X"; then
        IBAN_MASKED=true
    fi
fi

# 3. Check Views
CVW=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='GDPR_ADMIN' AND view_name='CUSTOMERS_ANON_VW';" "system" | tr -d '[:space:]')
if [ "${CVW:-0}" -gt 0 ] 2>/dev/null; then
    CUSTOMERS_VW_EXISTS=true
    # Verify view data masking
    UNMASKED_EMAILS=$(oracle_query_raw "SELECT COUNT(*) FROM gdpr_admin.customers_anon_vw a JOIN gdpr_admin.customers c ON a.customer_id = c.customer_id WHERE a.email = c.email;" "system" | tr -d '[:space:]')
    if [ "${UNMASKED_EMAILS:-99}" = "0" ] 2>/dev/null; then
        EMAIL_MASKED=true
    fi
fi

TVW=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='GDPR_ADMIN' AND view_name='TRANSACTIONS_ANON_VW';" "system" | tr -d '[:space:]')
if [ "${TVW:-0}" -gt 0 ] 2>/dev/null; then
    TRANS_VW_EXISTS=true
fi

SVW=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='GDPR_ADMIN' AND view_name='SUPPORT_TICKETS_ANON_VW';" "system" | tr -d '[:space:]')
if [ "${SVW:-0}" -gt 0 ] 2>/dev/null; then
    TICKETS_VW_EXISTS=true
    # Check if @ remains in text
    RAW_EMAILS=$(oracle_query_raw "SELECT COUNT(*) FROM gdpr_admin.support_tickets_anon_vw WHERE ticket_text LIKE '%@%';" "system" | tr -d '[:space:]')
    if [ "${RAW_EMAILS:-99}" = "0" ] 2>/dev/null; then
        TICKETS_REDACTED=true
    fi
fi

# 4. Check Scan Results
SCN=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='GDPR_ADMIN' AND table_name='PII_SCAN_RESULTS';" "system" | tr -d '[:space:]')
if [ "${SCN:-0}" -gt 0 ] 2>/dev/null; then
    PII_SCAN_TBL_EXISTS=true
    PII_SCAN_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM gdpr_admin.pii_scan_results;" "system" | tr -d '[:space:]')
    PII_SCAN_ROWS=${PII_SCAN_ROWS:-0}
    
    HAS_EMAIL=$(oracle_query_raw "SELECT COUNT(*) FROM gdpr_admin.pii_scan_results WHERE UPPER(pii_type) LIKE '%EMAIL%';" "system" | tr -d '[:space:]')
    if [ "${HAS_EMAIL:-0}" -gt 0 ] 2>/dev/null; then
        SCAN_FOUND_EMAIL=true
    fi
fi

# 5. Check Log Table
LOGT=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='GDPR_ADMIN' AND table_name='ANONYMIZATION_LOG';" "system" | tr -d '[:space:]')
if [ "${LOGT:-0}" -gt 0 ] 2>/dev/null; then
    LOG_TBL_EXISTS=true
    LOG_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM gdpr_admin.anonymization_log;" "system" | tr -d '[:space:]')
    LOG_ROWS=${LOG_ROWS:-0}
fi

# 6. Check CSV
CSV_PATH="/home/ga/anonymization_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(wc -c < "$CSV_PATH" 2>/dev/null || echo 0)
    
    TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo 0)
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo 0)
    if [ "$CSV_MTIME" -lt "$TASK_START" ]; then
        CSV_EXISTS=false # Pre-existing file
    fi
fi

# Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Export JSON
TEMP_JSON=$(mktemp /tmp/gdpr_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "pkg_exists": $PKG_EXISTS,
  "pkg_valid": $PKG_VALID,
  "func_count": $FUNC_COUNT,
  "deterministic_name": $DETERMINISTIC_NAME,
  "email_masked": $EMAIL_MASKED,
  "phone_masked": $PHONE_MASKED,
  "iban_masked": $IBAN_MASKED,
  "customers_vw_exists": $CUSTOMERS_VW_EXISTS,
  "trans_vw_exists": $TRANS_VW_EXISTS,
  "tickets_vw_exists": $TICKETS_VW_EXISTS,
  "pii_scan_tbl_exists": $PII_SCAN_TBL_EXISTS,
  "pii_scan_rows": $PII_SCAN_ROWS,
  "scan_found_email": $SCAN_FOUND_EMAIL,
  "log_tbl_exists": $LOG_TBL_EXISTS,
  "log_rows": $LOG_ROWS,
  "tickets_redacted": $TICKETS_REDACTED,
  "csv_exists": $CSV_EXISTS,
  "csv_size": $CSV_SIZE,
  ${GUI_EVIDENCE}
}
EOF

# Move securely
rm -f /tmp/gdpr_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/gdpr_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/gdpr_result.json
chmod 666 /tmp/gdpr_result.json 2>/dev/null || sudo chmod 666 /tmp/gdpr_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/gdpr_result.json"
cat /tmp/gdpr_result.json