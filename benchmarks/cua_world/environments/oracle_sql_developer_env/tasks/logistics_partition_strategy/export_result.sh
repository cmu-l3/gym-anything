#!/bin/bash
# Export results for Logistics Partition Strategy task
echo "=== Exporting Partitioning Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time

take_screenshot /tmp/task_final_state.png ga

# Initialize JSON fields
EVENTS_PART_EXISTS=false
EVENTS_PART_TYPE="NONE"
EVENTS_PART_COUNT=0
EVENTS_ROW_COUNT=0

SHIPMENTS_PART_EXISTS=false
SHIPMENTS_PART_TYPE="NONE"
SHIPMENTS_PART_COUNT=0
SHIPMENTS_ROW_COUNT=0

ANALYTICS_EXISTS=false
ANALYTICS_PART_TYPE="NONE"
ANALYTICS_SUBPART_TYPE="NONE"
ANALYTICS_PART_COUNT=0
ANALYTICS_ROW_COUNT=0

IDX_EVENTS_LOCAL=false
IDX_SHIPMENTS_LOCAL=false
IDX_ANALYTICS_LOCAL=false

P_FUTURE_EXISTS=false
P_FUTURE_ROW_COUNT=0

PARTITION_STATS_VW_EXISTS=false

PLAN_FILE_EXISTS=false
PLAN_FILE_CONTAINS_PRUNING=false
PLAN_FILE_MODIFIED_DURING_TASK=false

GUI_EVIDENCE=$(collect_gui_evidence)

# 1. Check SHIPMENT_EVENTS_PART
TBL_INFO=$(oracle_query_raw "SELECT partitioning_type, partition_count FROM user_part_tables WHERE table_name = 'SHIPMENT_EVENTS_PART';" "logistics_mgr" "Logistics2024" 2>/dev/null)
if [ -n "$TBL_INFO" ]; then
    EVENTS_PART_EXISTS=true
    EVENTS_PART_TYPE=$(echo "$TBL_INFO" | awk '{print $1}')
    EVENTS_PART_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tab_partitions WHERE table_name = 'SHIPMENT_EVENTS_PART';" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
    EVENTS_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM logistics_mgr.shipment_events_part;" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
    
    # Check Exchange Partition Future Row Count safely
    PF_COUNT_SQL="
    SET SERVEROUTPUT ON;
    DECLARE
      v_cnt NUMBER;
    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM logistics_mgr.shipment_events_part PARTITION (P_FUTURE)' INTO v_cnt;
      DBMS_OUTPUT.PUT_LINE('RES:' || v_cnt);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('RES:-1');
    END;
    /"
    PF_RES=$(echo "$PF_COUNT_SQL" | sudo docker exec -i oracle-xe sqlplus -s logistics_mgr/Logistics2024@//localhost:1521/XEPDB1 | grep "RES:" | cut -d':' -f2 | tr -d '[:space:]')
    
    if [ "$PF_RES" != "-1" ] && [ -n "$PF_RES" ]; then
        P_FUTURE_EXISTS=true
        P_FUTURE_ROW_COUNT=$PF_RES
    fi
fi

# 2. Check SHIPMENTS_PART
TBL_INFO2=$(oracle_query_raw "SELECT partitioning_type FROM user_part_tables WHERE table_name = 'SHIPMENTS_PART';" "logistics_mgr" "Logistics2024" 2>/dev/null)
if [ -n "$TBL_INFO2" ]; then
    SHIPMENTS_PART_EXISTS=true
    SHIPMENTS_PART_TYPE=$(echo "$TBL_INFO2" | awk '{print $1}')
    SHIPMENTS_PART_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tab_partitions WHERE table_name = 'SHIPMENTS_PART';" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
    SHIPMENTS_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM logistics_mgr.shipments_part;" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
fi

# 3. Check SHIPMENT_ANALYTICS (Composite)
TBL_INFO3=$(oracle_query_raw "SELECT partitioning_type, subpartitioning_type FROM user_part_tables WHERE table_name = 'SHIPMENT_ANALYTICS';" "logistics_mgr" "Logistics2024" 2>/dev/null)
if [ -n "$TBL_INFO3" ]; then
    ANALYTICS_EXISTS=true
    ANALYTICS_PART_TYPE=$(echo "$TBL_INFO3" | awk '{print $1}')
    ANALYTICS_SUBPART_TYPE=$(echo "$TBL_INFO3" | awk '{print $2}')
    ANALYTICS_PART_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tab_partitions WHERE table_name = 'SHIPMENT_ANALYTICS';" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
    ANALYTICS_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM logistics_mgr.shipment_analytics;" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
fi

# 4. Check Local Indexes
IDX1=$(oracle_query_raw "SELECT locality FROM user_part_indexes WHERE index_name = 'IDX_EVENTS_PART_SHIPID';" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
if [ "$IDX1" = "LOCAL" ]; then IDX_EVENTS_LOCAL=true; fi

IDX2=$(oracle_query_raw "SELECT locality FROM user_part_indexes WHERE index_name = 'IDX_SHIPMENTS_PART_CARRIER';" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
if [ "$IDX2" = "LOCAL" ]; then IDX_SHIPMENTS_LOCAL=true; fi

IDX3=$(oracle_query_raw "SELECT locality FROM user_part_indexes WHERE index_name = 'IDX_ANALYTICS_PART_CREATED';" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
if [ "$IDX3" = "LOCAL" ]; then IDX_ANALYTICS_LOCAL=true; fi

# 6. Check View
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_views WHERE view_name = 'PARTITION_STATS_VW';" "logistics_mgr" "Logistics2024" | tr -d '[:space:]')
if [ "$VW_CHECK" -gt 0 ] 2>/dev/null; then PARTITION_STATS_VW_EXISTS=true; fi

# 7. Check Pruning File
PLAN_FILE="/home/ga/Documents/exports/partition_pruning_plan.txt"
if [ -f "$PLAN_FILE" ]; then
    PLAN_FILE_EXISTS=true
    if grep -q "PARTITION RANGE" "$PLAN_FILE"; then
        PLAN_FILE_CONTAINS_PRUNING=true
    fi
    
    START_TIME=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
    MOD_TIME=$(stat -c %Y "$PLAN_FILE" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$START_TIME" ]; then
        PLAN_FILE_MODIFIED_DURING_TASK=true
    fi
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/logistics_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "events_part_exists": $EVENTS_PART_EXISTS,
    "events_part_type": "$EVENTS_PART_TYPE",
    "events_part_count": ${EVENTS_PART_COUNT:-0},
    "events_row_count": ${EVENTS_ROW_COUNT:-0},
    
    "shipments_part_exists": $SHIPMENTS_PART_EXISTS,
    "shipments_part_type": "$SHIPMENTS_PART_TYPE",
    "shipments_part_count": ${SHIPMENTS_PART_COUNT:-0},
    "shipments_row_count": ${SHIPMENTS_ROW_COUNT:-0},
    
    "analytics_exists": $ANALYTICS_EXISTS,
    "analytics_part_type": "$ANALYTICS_PART_TYPE",
    "analytics_subpart_type": "$ANALYTICS_SUBPART_TYPE",
    "analytics_part_count": ${ANALYTICS_PART_COUNT:-0},
    "analytics_row_count": ${ANALYTICS_ROW_COUNT:-0},
    
    "idx_events_local": $IDX_EVENTS_LOCAL,
    "idx_shipments_local": $IDX_SHIPMENTS_LOCAL,
    "idx_analytics_local": $IDX_ANALYTICS_LOCAL,
    
    "p_future_exists": $P_FUTURE_EXISTS,
    "p_future_row_count": ${P_FUTURE_ROW_COUNT:-0},
    
    "partition_stats_vw_exists": $PARTITION_STATS_VW_EXISTS,
    
    "plan_file_exists": $PLAN_FILE_EXISTS,
    "plan_file_contains_pruning": $PLAN_FILE_CONTAINS_PRUNING,
    "plan_file_modified_during_task": $PLAN_FILE_MODIFIED_DURING_TASK,
    
    $GUI_EVIDENCE
}
EOF

# Move securely
cp "$TEMP_JSON" /tmp/logistics_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/logistics_result.json
chmod 666 /tmp/logistics_result.json 2>/dev/null || sudo chmod 666 /tmp/logistics_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/logistics_result.json"
cat /tmp/logistics_result.json
echo "=== Export Complete ==="