#!/bin/bash
# Export results for Insurance Claims Fraud Detection task
echo "=== Exporting Claims Fraud Detection results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Sanitize: ensure a variable holds a valid integer, default to given fallback
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize all flags
PKG_EXISTS=false
PKG_VALID=false
BENFORD_FUNC_EXISTS=false
OUTLIER_FUNC_EXISTS=false
DUPLICATE_PROC_EXISTS=false
UPCODING_PROC_EXISTS=false
FRAUD_FLAGS_TABLE_EXISTS=false
FRAUD_FLAGS_COUNT=0
FRAUD_SUMMARY_MV_EXISTS=false
CSV_EXISTS=false
CSV_SIZE=0
CSV_HAS_FLAG_TYPES=false
PIPELINED_USED=false
BENFORD_FLAGS=0
OUTLIER_FLAGS=0
DUPLICATE_FLAGS=0
UPCODING_FLAGS=0
TEMPORAL_FLAGS=0

# --- Check FRAUD_DETECTION_PKG exists and is valid ---
PKG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'CLAIMS_ANALYST' AND object_name = 'FRAUD_DETECTION_PKG' AND object_type = 'PACKAGE';" "system" | tr -d '[:space:]')
if [ "${PKG_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PKG_EXISTS=true
fi

PKG_VALID_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'CLAIMS_ANALYST' AND object_name = 'FRAUD_DETECTION_PKG' AND object_type = 'PACKAGE BODY' AND status = 'VALID';" "system" | tr -d '[:space:]')
if [ "${PKG_VALID_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PKG_VALID=true
fi

# --- Check individual package components ---
# Check for BENFORD_ANALYSIS function (should be pipelined)
BENFORD_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'CLAIMS_ANALYST' AND object_name = 'FRAUD_DETECTION_PKG' AND procedure_name = 'BENFORD_ANALYSIS';" "system" | tr -d '[:space:]')
if [ "${BENFORD_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    BENFORD_FUNC_EXISTS=true
fi

# Check for pipelined keyword in package source
PKG_SOURCE=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'CLAIMS_ANALYST' AND name = 'FRAUD_DETECTION_PKG' AND type IN ('PACKAGE','PACKAGE BODY') ORDER BY type, line;" "system" 2>/dev/null)
if echo "$PKG_SOURCE" | grep -qiE "PIPELINED" 2>/dev/null; then
    PIPELINED_USED=true
fi

OUTLIER_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'CLAIMS_ANALYST' AND object_name = 'FRAUD_DETECTION_PKG' AND procedure_name = 'FIND_STATISTICAL_OUTLIERS';" "system" | tr -d '[:space:]')
if [ "${OUTLIER_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    OUTLIER_FUNC_EXISTS=true
fi

DUP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'CLAIMS_ANALYST' AND object_name = 'FRAUD_DETECTION_PKG' AND procedure_name = 'DETECT_DUPLICATES';" "system" | tr -d '[:space:]')
if [ "${DUP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DUPLICATE_PROC_EXISTS=true
fi

UPCODE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'CLAIMS_ANALYST' AND object_name = 'FRAUD_DETECTION_PKG' AND procedure_name = 'DETECT_UPCODING';" "system" | tr -d '[:space:]')
if [ "${UPCODE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    UPCODING_PROC_EXISTS=true
fi

# --- Check FRAUD_FLAGS table ---
FF_TABLE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'CLAIMS_ANALYST' AND table_name = 'FRAUD_FLAGS';" "system" | tr -d '[:space:]')
if [ "${FF_TABLE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FRAUD_FLAGS_TABLE_EXISTS=true

    # Count total flags
    FRAUD_FLAGS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM claims_analyst.fraud_flags;" "system" | tr -d '[:space:]')
    FRAUD_FLAGS_COUNT=${FRAUD_FLAGS_COUNT:-0}

    # Count by type
    BENFORD_FLAGS=$(oracle_query_raw "SELECT COUNT(*) FROM claims_analyst.fraud_flags WHERE flag_type = 'BENFORDS_LAW';" "system" | tr -d '[:space:]')
    BENFORD_FLAGS=${BENFORD_FLAGS:-0}

    OUTLIER_FLAGS=$(oracle_query_raw "SELECT COUNT(*) FROM claims_analyst.fraud_flags WHERE flag_type = 'STATISTICAL_OUTLIER';" "system" | tr -d '[:space:]')
    OUTLIER_FLAGS=${OUTLIER_FLAGS:-0}

    DUPLICATE_FLAGS=$(oracle_query_raw "SELECT COUNT(*) FROM claims_analyst.fraud_flags WHERE flag_type = 'DUPLICATE_CLAIM';" "system" | tr -d '[:space:]')
    DUPLICATE_FLAGS=${DUPLICATE_FLAGS:-0}

    UPCODING_FLAGS=$(oracle_query_raw "SELECT COUNT(*) FROM claims_analyst.fraud_flags WHERE flag_type = 'UPCODING';" "system" | tr -d '[:space:]')
    UPCODING_FLAGS=${UPCODING_FLAGS:-0}

    TEMPORAL_FLAGS=$(oracle_query_raw "SELECT COUNT(*) FROM claims_analyst.fraud_flags WHERE flag_type = 'TEMPORAL_CLUSTER';" "system" | tr -d '[:space:]')
    TEMPORAL_FLAGS=${TEMPORAL_FLAGS:-0}
fi

# --- Check FRAUD_SUMMARY_MV ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'CLAIMS_ANALYST' AND mview_name = 'FRAUD_SUMMARY_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FRAUD_SUMMARY_MV_EXISTS=true
fi

# --- Check CSV export ---
CSV_PATH="/home/ga/fraud_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(wc -c < "$CSV_PATH" 2>/dev/null)
    CSV_SIZE=${CSV_SIZE:-0}

    if grep -qiE "BENFORDS_LAW|STATISTICAL_OUTLIER|DUPLICATE_CLAIM|UPCODING|TEMPORAL" "$CSV_PATH" 2>/dev/null; then
        CSV_HAS_FLAG_TYPES=true
    fi
fi

# --- Check for object types (used by pipelined function return type) ---
OBJ_TYPE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_types WHERE owner = 'CLAIMS_ANALYST';" "system" | tr -d '[:space:]')
OBJ_TYPE_COUNT=${OBJ_TYPE_COUNT:-0}

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Sanitize all numeric variables before JSON output
FRAUD_FLAGS_COUNT=$(sanitize_int "$FRAUD_FLAGS_COUNT" 0)
BENFORD_FLAGS=$(sanitize_int "$BENFORD_FLAGS" 0)
OUTLIER_FLAGS=$(sanitize_int "$OUTLIER_FLAGS" 0)
DUPLICATE_FLAGS=$(sanitize_int "$DUPLICATE_FLAGS" 0)
UPCODING_FLAGS=$(sanitize_int "$UPCODING_FLAGS" 0)
TEMPORAL_FLAGS=$(sanitize_int "$TEMPORAL_FLAGS" 0)
OBJ_TYPE_COUNT=$(sanitize_int "$OBJ_TYPE_COUNT" 0)
CSV_SIZE=$(sanitize_int "$CSV_SIZE" 0)

# --- Write result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "package_exists": $PKG_EXISTS,
    "package_body_valid": $PKG_VALID,
    "benford_function_exists": $BENFORD_FUNC_EXISTS,
    "pipelined_used": $PIPELINED_USED,
    "outlier_function_exists": $OUTLIER_FUNC_EXISTS,
    "duplicate_proc_exists": $DUPLICATE_PROC_EXISTS,
    "upcoding_proc_exists": $UPCODING_PROC_EXISTS,
    "fraud_flags_table_exists": $FRAUD_FLAGS_TABLE_EXISTS,
    "fraud_flags_count": ${FRAUD_FLAGS_COUNT:-0},
    "benford_flags": ${BENFORD_FLAGS:-0},
    "outlier_flags": ${OUTLIER_FLAGS:-0},
    "duplicate_flags": ${DUPLICATE_FLAGS:-0},
    "upcoding_flags": ${UPCODING_FLAGS:-0},
    "temporal_flags": ${TEMPORAL_FLAGS:-0},
    "fraud_summary_mv_exists": $FRAUD_SUMMARY_MV_EXISTS,
    "object_type_count": ${OBJ_TYPE_COUNT:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_size": ${CSV_SIZE:-0},
    "csv_has_flag_types": $CSV_HAS_FLAG_TYPES,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/claims_fraud_result.json 2>/dev/null || sudo rm -f /tmp/claims_fraud_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/claims_fraud_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/claims_fraud_result.json
chmod 666 /tmp/claims_fraud_result.json 2>/dev/null || sudo chmod 666 /tmp/claims_fraud_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/claims_fraud_result.json"
cat /tmp/claims_fraud_result.json
echo "=== Export complete ==="
