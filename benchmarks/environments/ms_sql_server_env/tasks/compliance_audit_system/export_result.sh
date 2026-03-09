#!/bin/bash
# Export results for compliance_audit_system task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Helper: run query against ComplianceDB
compliance_query() {
    mssql_query "$1" "ComplianceDB"
}

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# ── Check: ComplianceDB database exists ──────────────────────────────────────
DB_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    DC=$(mssql_query "SELECT COUNT(*) FROM sys.databases WHERE name = 'ComplianceDB'" "master" | tr -d ' \r\n')
    [ "${DC:-0}" -gt 0 ] 2>/dev/null && DB_EXISTS="true"
fi

# ── Check: audit schema ───────────────────────────────────────────────────────
AUDIT_SCHEMA_EXISTS="false"
if [ "$DB_EXISTS" = "true" ]; then
    SC=$(compliance_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'audit'" | tr -d ' \r\n')
    [ "${SC:-0}" -gt 0 ] 2>/dev/null && AUDIT_SCHEMA_EXISTS="true"
fi

# ── Check: Encryption objects ─────────────────────────────────────────────────
MASTER_KEY_EXISTS="false"
CERTIFICATE_EXISTS="false"
SYMMETRIC_KEY_EXISTS="false"

if [ "$DB_EXISTS" = "true" ]; then
    MK=$(compliance_query "SELECT COUNT(*) FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##'" | tr -d ' \r\n')
    [ "${MK:-0}" -gt 0 ] 2>/dev/null && MASTER_KEY_EXISTS="true"

    CERT=$(compliance_query "SELECT COUNT(*) FROM sys.certificates WHERE name = 'AuditDataCert'" | tr -d ' \r\n')
    [ "${CERT:-0}" -gt 0 ] 2>/dev/null && CERTIFICATE_EXISTS="true"

    SK=$(compliance_query "SELECT COUNT(*) FROM sys.symmetric_keys WHERE name = 'SSNEncryptionKey'" | tr -d ' \r\n')
    [ "${SK:-0}" -gt 0 ] 2>/dev/null && SYMMETRIC_KEY_EXISTS="true"
fi

# ── Check: audit.SensitiveEmployeeData table ──────────────────────────────────
SENSITIVE_TABLE_EXISTS="false"
SENSITIVE_ROW_COUNT=0
SENSITIVE_COLUMNS_FOUND=""
HAS_SENSITIVE_COLUMNS="false"
ENCRYPTION_WORKING="false"

if [ "$DB_EXISTS" = "true" ]; then
    STC=$(compliance_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('audit.SensitiveEmployeeData') AND type = 'U'" | tr -d ' \r\n')
    [ "${STC:-0}" -gt 0 ] 2>/dev/null && SENSITIVE_TABLE_EXISTS="true"

    if [ "$SENSITIVE_TABLE_EXISTS" = "true" ]; then
        SENSITIVE_COLUMNS_FOUND=$(compliance_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'audit' AND TABLE_NAME = 'SensitiveEmployeeData'
            ORDER BY ORDINAL_POSITION
        " | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        REQUIRED_SENSITIVE_COLS=("RecordID" "SSN_Encrypted" "FirstName" "LastName" "DateOfBirth")
        scols_lower=$(echo "$SENSITIVE_COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        FOUND_SCOLS=0
        for col in "${REQUIRED_SENSITIVE_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            if echo "$scols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
                FOUND_SCOLS=$((FOUND_SCOLS + 1))
            fi
        done
        [ "$FOUND_SCOLS" -ge 4 ] && HAS_SENSITIVE_COLUMNS="true"

        SENSITIVE_ROW_COUNT=$(compliance_query "SELECT COUNT(*) FROM audit.SensitiveEmployeeData" 2>/dev/null | tr -d ' \r\n'; true)
        SENSITIVE_ROW_COUNT=${SENSITIVE_ROW_COUNT:-0}

        # Check that SSN_Encrypted has non-NULL non-zero binary data
        if echo "$scols_lower" | grep -q "ssn_encrypted"; then
            ENC_COUNT=$(compliance_query "SELECT COUNT(*) FROM audit.SensitiveEmployeeData WHERE SSN_Encrypted IS NOT NULL AND LEN(SSN_Encrypted) > 0" 2>/dev/null | tr -d ' \r\n'; true)
            [ "${ENC_COUNT:-0}" -gt 0 ] 2>/dev/null && ENCRYPTION_WORKING="true"
        fi
    fi
fi

# ── Check: audit.AuditLog table ───────────────────────────────────────────────
AUDIT_LOG_EXISTS="false"
AUDIT_LOG_ROW_COUNT=0
AUDIT_LOG_COLUMNS_FOUND=""
HAS_AUDIT_LOG_COLUMNS="false"

if [ "$DB_EXISTS" = "true" ]; then
    ALC=$(compliance_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('audit.AuditLog') AND type = 'U'" | tr -d ' \r\n')
    [ "${ALC:-0}" -gt 0 ] 2>/dev/null && AUDIT_LOG_EXISTS="true"

    if [ "$AUDIT_LOG_EXISTS" = "true" ]; then
        AUDIT_LOG_COLUMNS_FOUND=$(compliance_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'audit' AND TABLE_NAME = 'AuditLog'
            ORDER BY ORDINAL_POSITION
        " | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        REQUIRED_LOG_COLS=("LogID" "EventType" "TableName" "AffectedRecordID" "EventTimestamp")
        lcols_lower=$(echo "$AUDIT_LOG_COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        FOUND_LCOLS=0
        for col in "${REQUIRED_LOG_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            if echo "$lcols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
                FOUND_LCOLS=$((FOUND_LCOLS + 1))
            fi
        done
        [ "$FOUND_LCOLS" -ge 4 ] && HAS_AUDIT_LOG_COLUMNS="true"

        AUDIT_LOG_ROW_COUNT=$(compliance_query "SELECT COUNT(*) FROM audit.AuditLog" 2>/dev/null | tr -d ' \r\n'; true)
        AUDIT_LOG_ROW_COUNT=${AUDIT_LOG_ROW_COUNT:-0}
    fi
fi

# ── Check: Stored procedure exists ───────────────────────────────────────────
PROC_EXISTS="false"
if [ "$DB_EXISTS" = "true" ]; then
    PC=$(compliance_query "
        SELECT COUNT(*) FROM sys.procedures p
        JOIN sys.schemas s ON p.schema_id = s.schema_id
        WHERE p.name = 'usp_InsertSensitiveRecord' AND s.name = 'audit'
    " | tr -d ' \r\n')
    [ "${PC:-0}" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"
fi

# ── Check: Trigger exists ─────────────────────────────────────────────────────
TRIGGER_EXISTS="false"
if [ "$DB_EXISTS" = "true" ] && [ "$SENSITIVE_TABLE_EXISTS" = "true" ]; then
    TRG=$(compliance_query "
        SELECT COUNT(*) FROM sys.triggers t
        WHERE t.parent_id = OBJECT_ID('audit.SensitiveEmployeeData')
        AND t.name LIKE '%Insert%'
    " | tr -d ' \r\n')
    [ "${TRG:-0}" -gt 0 ] 2>/dev/null && TRIGGER_EXISTS="true"
fi

# Build JSON result
cat > /tmp/compliance_result.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "db_exists": $DB_EXISTS,
    "audit_schema_exists": $AUDIT_SCHEMA_EXISTS,
    "master_key_exists": $MASTER_KEY_EXISTS,
    "certificate_exists": $CERTIFICATE_EXISTS,
    "symmetric_key_exists": $SYMMETRIC_KEY_EXISTS,
    "sensitive_table_exists": $SENSITIVE_TABLE_EXISTS,
    "sensitive_row_count": ${SENSITIVE_ROW_COUNT:-0},
    "has_sensitive_columns": $HAS_SENSITIVE_COLUMNS,
    "sensitive_columns_found": "$SENSITIVE_COLUMNS_FOUND",
    "encryption_working": $ENCRYPTION_WORKING,
    "audit_log_exists": $AUDIT_LOG_EXISTS,
    "audit_log_row_count": ${AUDIT_LOG_ROW_COUNT:-0},
    "has_audit_log_columns": $HAS_AUDIT_LOG_COLUMNS,
    "audit_log_columns_found": "$AUDIT_LOG_COLUMNS_FOUND",
    "proc_exists": $PROC_EXISTS,
    "trigger_exists": $TRIGGER_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/compliance_result.json 2>/dev/null || true
echo "Result saved to /tmp/compliance_result.json"
cat /tmp/compliance_result.json
echo ""
echo "=== Export complete ==="
exit 0
