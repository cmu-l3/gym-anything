#!/bin/bash
# Export script for Retail SCD2 Dimension Modeling task
echo "=== Exporting Retail SCD2 Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

sanitize_int() { local val="$1" default="$2"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "$default"; fi; }

# Initialize checks
SMARTHOME_LOADED_COUNT=0
TRIGGER_EXISTS=false
DYNAMIC_TEST_PASSED=false
OLD_RECORD_EXPIRED=false
NEW_RECORD_CREATED=false
HISTORICAL_VW_EXISTS=false
HISTORICAL_VW_VALUE=0
ANOMALY_VW_EXISTS=false
ANOMALY_VW_COUNT=0
ANOMALY_VW_CORRECT=false

# 1. Check Initial Load
SH_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM retail_admin.dim_products WHERE category = 'SmartHome' AND is_current = 'Y';" "system" | tr -d '[:space:]')
SMARTHOME_LOADED_COUNT=$(sanitize_int "$SH_COUNT" 0)

# 2. Check Trigger Exists
TRG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM dba_triggers WHERE owner = 'RETAIL_ADMIN' AND trigger_name = 'TRG_PRODUCT_SCD2' AND status = 'ENABLED';" "system" | tr -d '[:space:]')
if [ "$(sanitize_int "$TRG_CHECK" 0)" -gt 0 ]; then
    TRIGGER_EXISTS=true
    
    # DYNAMIC ANTI-GAMING TEST: Trigger the SCD update on product 8000
    echo "Running dynamic trigger test..."
    oracle_query "UPDATE retail_admin.source_products SET unit_price = 999.99, last_updated = SYSDATE WHERE product_id = 8000; COMMIT;" "retail_admin" "Retail2024" > /dev/null 2>&1
    
    # Did the old record expire correctly?
    EXP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM retail_admin.dim_products WHERE product_id = 8000 AND is_current = 'N' AND TRUNC(valid_to) = TRUNC(SYSDATE);" "system" | tr -d '[:space:]')
    if [ "$(sanitize_int "$EXP_CHECK" 0)" -gt 0 ]; then
        OLD_RECORD_EXPIRED=true
    fi
    
    # Was the new record created correctly?
    NEW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM retail_admin.dim_products WHERE product_id = 8000 AND is_current = 'Y' AND unit_price = 999.99 AND valid_to = TO_DATE('9999-12-31', 'YYYY-MM-DD');" "system" | tr -d '[:space:]')
    if [ "$(sanitize_int "$NEW_CHECK" 0)" -gt 0 ]; then
        NEW_RECORD_CREATED=true
    fi
    
    if [ "$OLD_RECORD_EXPIRED" = "true" ] && [ "$NEW_RECORD_CREATED" = "true" ]; then
        DYNAMIC_TEST_PASSED=true
    fi
fi

# 3. Check Historical View
HIST_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM dba_views WHERE owner = 'RETAIL_ADMIN' AND view_name = 'HISTORICAL_SALES_REVENUE_VW';" "system" | tr -d '[:space:]')
if [ "$(sanitize_int "$HIST_CHECK" 0)" -gt 0 ]; then
    HISTORICAL_VW_EXISTS=true
    # Test line_total calculation. Product 8000 at 2022-01-01 was 100.00. Qty 2 = 200.
    VAL_CHECK=$(oracle_query_raw "SELECT line_total FROM retail_admin.historical_sales_revenue_vw WHERE sale_id = 1;" "system" | tr -d '[:space:]')
    HISTORICAL_VW_VALUE=$(sanitize_int "$VAL_CHECK" 0)
fi

# 4. Check Anomaly View
ANOM_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM dba_views WHERE owner = 'RETAIL_ADMIN' AND view_name = 'SCD2_OVERLAP_ANOMALIES_VW';" "system" | tr -d '[:space:]')
if [ "$(sanitize_int "$ANOM_CHECK" 0)" -gt 0 ]; then
    ANOMALY_VW_EXISTS=true
    ANOM_CNT=$(oracle_query_raw "SELECT COUNT(*) FROM retail_admin.scd2_overlap_anomalies_vw;" "system" | tr -d '[:space:]')
    ANOMALY_VW_COUNT=$(sanitize_int "$ANOM_CNT" 0)
    
    # Are they exactly the 5 bad products? (9001-9005)
    CORRECT_CNT=$(oracle_query_raw "SELECT COUNT(*) FROM retail_admin.scd2_overlap_anomalies_vw WHERE product_id IN (9001, 9002, 9003, 9004, 9005);" "system" | tr -d '[:space:]')
    if [ "$(sanitize_int "$CORRECT_CNT" 0)" -eq 5 ] && [ "$ANOMALY_VW_COUNT" -eq 5 ]; then
        ANOMALY_VW_CORRECT=true
    fi
fi

# 5. Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON Report
TEMP_JSON=$(mktemp /tmp/retail_scd2_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "smarthome_loaded_count": $SMARTHOME_LOADED_COUNT,
    "trigger_exists": $TRIGGER_EXISTS,
    "dynamic_test_passed": $DYNAMIC_TEST_PASSED,
    "old_record_expired": $OLD_RECORD_EXPIRED,
    "new_record_created": $NEW_RECORD_CREATED,
    "historical_vw_exists": $HISTORICAL_VW_EXISTS,
    "historical_vw_value": $HISTORICAL_VW_VALUE,
    "anomaly_vw_exists": $ANOMALY_VW_EXISTS,
    "anomaly_vw_count": $ANOMALY_VW_COUNT,
    "anomaly_vw_correct": $ANOMALY_VW_CORRECT,
    $GUI_EVIDENCE
}
EOF

sudo mv "$TEMP_JSON" /tmp/retail_scd2_result.json
sudo chmod 666 /tmp/retail_scd2_result.json

echo "Results exported to /tmp/retail_scd2_result.json"
cat /tmp/retail_scd2_result.json
echo "=== Export Complete ==="