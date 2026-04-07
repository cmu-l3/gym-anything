#!/bin/bash
# Export results for Multi-Tenant Data Isolation task
echo "=== Exporting Multi-Tenant VPD results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Sanitize: ensure a variable holds a valid integer, default to given fallback
sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize all flags
POLICY_FUNCTION_FIXED=false
FINANCIAL_POLICY_EXISTS=false
CONTEXT_DEFAULT_FIXED=false
AUDIT_LOG_TABLE_EXISTS=false
VIOLATION_VW_EXISTS=false
AUDIT_PROC_EXISTS=false
TENANT1_ISOLATED=false
TENANT2_ISOLATED=false
TENANT3_ISOLATED=false

# --- Check if TENANT_ISOLATION_POLICY function is fixed ---
# The fixed function should return '1=0' (deny all) when context is NULL or 0, not NULL (allow all)
POLICY_TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'SAAS_ADMIN' AND name = 'TENANT_ISOLATION_POLICY' AND type = 'FUNCTION' ORDER BY line;" "system" 2>/dev/null)

# Check if the function now returns '1=0' instead of NULL for the null/zero case
if echo "$POLICY_TEXT" | grep -qiE "1\s*=\s*0|RETURN\s*'1=0'" 2>/dev/null; then
    # Also verify it does NOT return NULL for the null case
    if ! echo "$POLICY_TEXT" | grep -qiE "RETURN\s+NULL" 2>/dev/null; then
        POLICY_FUNCTION_FIXED=true
    fi
fi

# Also accept: the function was replaced entirely with a correct implementation
# Check by testing: when no context is set, does the policy block access?
POLICY_FN_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'SAAS_ADMIN' AND object_name = 'TENANT_ISOLATION_POLICY' AND object_type = 'FUNCTION' AND status = 'VALID';" "system" | tr -d '[:space:]')
POLICY_FN_COUNT=${POLICY_FN_COUNT:-0}

# --- Check if FINANCIAL_RECORDS has a VPD policy now ---
FIN_POLICY_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_policies WHERE object_owner = 'SAAS_ADMIN' AND object_name = 'FINANCIAL_RECORDS';" "system" | tr -d '[:space:]')
if [ "${FIN_POLICY_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FINANCIAL_POLICY_EXISTS=true
fi

# Count total VPD policies on saas_admin tables
TOTAL_POLICIES=$(oracle_query_raw "SELECT COUNT(*) FROM all_policies WHERE object_owner = 'SAAS_ADMIN';" "system" | tr -d '[:space:]')
TOTAL_POLICIES=${TOTAL_POLICIES:-0}

# --- Check if application context default is fixed ---
# The context package should default to -1 (no access) not 0 (superuser)
CTX_PKG_TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'SAAS_ADMIN' AND name = 'TENANT_CTX_PKG' AND type = 'PACKAGE BODY' ORDER BY line;" "system" 2>/dev/null)

if echo "$CTX_PKG_TEXT" | grep -qiE "'-1'|'\\-1'" 2>/dev/null; then
    CONTEXT_DEFAULT_FIXED=true
fi
# Also check the old bug is gone (no more defaulting to '0')
STILL_HAS_ZERO_DEFAULT=false
if echo "$CTX_PKG_TEXT" | grep -qiE "SET_CONTEXT.*TENANT_ID.*'0'" 2>/dev/null; then
    STILL_HAS_ZERO_DEFAULT=true
    CONTEXT_DEFAULT_FIXED=false
fi

# --- Check SECURITY_AUDIT_LOG table ---
AUDIT_TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'SAAS_ADMIN' AND table_name = 'SECURITY_AUDIT_LOG';" "system" | tr -d '[:space:]')
if [ "${AUDIT_TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    AUDIT_LOG_TABLE_EXISTS=true
fi

# --- Check CROSS_TENANT_VIOLATION_VW ---
VIOLATION_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SAAS_ADMIN' AND view_name = 'CROSS_TENANT_VIOLATION_VW';" "system" | tr -d '[:space:]')
if [ "${VIOLATION_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIOLATION_VW_EXISTS=true
fi

# --- Check PROC_SECURITY_AUDIT_REPORT ---
AUDIT_PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'SAAS_ADMIN' AND object_name = 'PROC_SECURITY_AUDIT_REPORT';" "system" | tr -d '[:space:]')
if [ "${AUDIT_PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    AUDIT_PROC_EXISTS=true
fi

# --- Test actual tenant isolation ---
# Test: tenant1_user should only see tenant_id=1 rows in CUSTOMER_DATA
# We need to set context and then query. Use PL/SQL block.
T1_CUSTOMER_COUNT=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT DISTINCT tenant_id FROM saas_admin.customer_data
    WHERE tenant_id != 1
) WHERE ROWNUM = 1;" "tenant1_user/Tenant1Pass" 2>/dev/null | tr -d '[:space:]')
# If tenant1 sees 0 rows with tenant_id != 1, isolation works
if [ "${T1_CUSTOMER_COUNT:-1}" = "0" ] 2>/dev/null; then
    TENANT1_ISOLATED=true
fi

T2_CUSTOMER_COUNT=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT DISTINCT tenant_id FROM saas_admin.customer_data
    WHERE tenant_id != 2
) WHERE ROWNUM = 1;" "tenant2_user/Tenant2Pass" 2>/dev/null | tr -d '[:space:]')
if [ "${T2_CUSTOMER_COUNT:-1}" = "0" ] 2>/dev/null; then
    TENANT2_ISOLATED=true
fi

T3_CUSTOMER_COUNT=$(oracle_query_raw "
SELECT COUNT(*) FROM (
    SELECT DISTINCT tenant_id FROM saas_admin.customer_data
    WHERE tenant_id != 3
) WHERE ROWNUM = 1;" "tenant3_user/Tenant3Pass" 2>/dev/null | tr -d '[:space:]')
if [ "${T3_CUSTOMER_COUNT:-1}" = "0" ] 2>/dev/null; then
    TENANT3_ISOLATED=true
fi

# Test financial records isolation too
T1_FIN_ISOLATED=false
T1_FIN_CHECK=$(oracle_query_raw "
SELECT COUNT(*) FROM saas_admin.financial_records WHERE tenant_id != 1;" "tenant1_user/Tenant1Pass" 2>/dev/null | tr -d '[:space:]')
if [ "${T1_FIN_CHECK:-1}" = "0" ] 2>/dev/null; then
    T1_FIN_ISOLATED=true
fi

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Sanitize all numeric variables before JSON output
POLICY_FN_COUNT=$(sanitize_int "$POLICY_FN_COUNT" 0)
TOTAL_POLICIES=$(sanitize_int "$TOTAL_POLICIES" 0)

# --- Write result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "policy_function_fixed": $POLICY_FUNCTION_FIXED,
    "policy_function_valid": ${POLICY_FN_COUNT:-0},
    "financial_policy_exists": $FINANCIAL_POLICY_EXISTS,
    "total_vpd_policies": ${TOTAL_POLICIES:-0},
    "context_default_fixed": $CONTEXT_DEFAULT_FIXED,
    "still_has_zero_default": $STILL_HAS_ZERO_DEFAULT,
    "audit_log_table_exists": $AUDIT_LOG_TABLE_EXISTS,
    "violation_vw_exists": $VIOLATION_VW_EXISTS,
    "audit_proc_exists": $AUDIT_PROC_EXISTS,
    "tenant1_customer_isolated": $TENANT1_ISOLATED,
    "tenant2_customer_isolated": $TENANT2_ISOLATED,
    "tenant3_customer_isolated": $TENANT3_ISOLATED,
    "tenant1_financial_isolated": $T1_FIN_ISOLATED,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/multi_tenant_result.json 2>/dev/null || sudo rm -f /tmp/multi_tenant_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/multi_tenant_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/multi_tenant_result.json
chmod 666 /tmp/multi_tenant_result.json 2>/dev/null || sudo chmod 666 /tmp/multi_tenant_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/multi_tenant_result.json"
cat /tmp/multi_tenant_result.json
echo "=== Export complete ==="
