#!/bin/bash
# Export results for Streaming Royalty Apportionment task
echo "=== Exporting Royalty Apportionment results ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png ga

# Sanitize helpers
sanitize_float() { local val="$1" default="$2"; if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then echo "$val"; else echo "$default"; fi; }

# Track evaluation metrics
VW_REVENUE_EXISTS=false
T1_REVENUE=0
VW_INVALID_EXISTS=false
INVALID_TRACKS=""
SUSPENSE_EXISTS=false
SUSPENSE_TOTAL=0
MV_PAYOUT_EXISTS=false
ALICE_PAYOUT=0
ALICE_TRACK_COUNT=0
ALICE_TOP_TRACK=""

# 1. Check VW_TRACK_REVENUE
REV_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ROYALTY_ADMIN' AND view_name = 'VW_TRACK_REVENUE';" "system" | tr -d '[:space:]')
if [ "${REV_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VW_REVENUE_EXISTS=true
    T1_REVENUE=$(oracle_query_raw "SELECT total_revenue FROM royalty_admin.vw_track_revenue WHERE track_id='T1';" "system" | tr -d '[:space:]')
    T1_REVENUE=$(sanitize_float "$T1_REVENUE" "0")
fi

# 2. Check VW_INVALID_SPLITS
INV_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'ROYALTY_ADMIN' AND view_name = 'VW_INVALID_SPLITS';" "system" | tr -d '[:space:]')
if [ "${INV_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VW_INVALID_EXISTS=true
    # Expecting 'T2,T4'
    INVALID_TRACKS=$(oracle_query_raw "SELECT LISTAGG(track_id, ',') WITHIN GROUP (ORDER BY track_id) FROM royalty_admin.vw_invalid_splits;" "system" | tr -d '[:space:]')
fi

# 3. Check SUSPENSE_BALANCES
SUSP_TB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'ROYALTY_ADMIN' AND table_name = 'SUSPENSE_BALANCES';" "system" | tr -d '[:space:]')
if [ "${SUSP_TB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SUSPENSE_EXISTS=true
    # Total suspense should be 39.75 (T2: 37.50, T4: 2.25)
    SUSPENSE_TOTAL=$(oracle_query_raw "SELECT SUM(withheld_revenue) FROM royalty_admin.suspense_balances;" "system" | tr -d '[:space:]')
    SUSPENSE_TOTAL=$(sanitize_float "$SUSPENSE_TOTAL" "0")
fi

# 4. Check MV_ROYALTY_STATEMENTS
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'ROYALTY_ADMIN' AND mview_name = 'MV_ROYALTY_STATEMENTS';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MV_PAYOUT_EXISTS=true
    # Alice is holder_id 1
    # Expected payout: 5.25(T1) + 15.00(T3) + 56.25(T5) = 76.50
    ALICE_PAYOUT=$(oracle_query_raw "SELECT total_payout FROM royalty_admin.mv_royalty_statements WHERE holder_id=1;" "system" | tr -d '[:space:]')
    ALICE_PAYOUT=$(sanitize_float "$ALICE_PAYOUT" "0")
    
    ALICE_TRACK_COUNT=$(oracle_query_raw "SELECT track_count FROM royalty_admin.mv_royalty_statements WHERE holder_id=1;" "system" | tr -d '[:space:]')
    ALICE_TRACK_COUNT=$(sanitize_float "$ALICE_TRACK_COUNT" "0")
    
    ALICE_TOP_TRACK=$(oracle_query_raw "SELECT top_earning_track FROM royalty_admin.mv_royalty_statements WHERE holder_id=1;" "system" | tr -d '\r\n')
fi

# 5. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/q3_payouts.csv"
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_ROWS="0"
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    
    OUTPUT_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 6. Gather GUI usage evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "vw_revenue_exists": $VW_REVENUE_EXISTS,
    "t1_revenue": $T1_REVENUE,
    "vw_invalid_exists": $VW_INVALID_EXISTS,
    "invalid_tracks": "$INVALID_TRACKS",
    "suspense_exists": $SUSPENSE_EXISTS,
    "suspense_total": $SUSPENSE_TOTAL,
    "mv_payout_exists": $MV_PAYOUT_EXISTS,
    "alice_payout": $ALICE_PAYOUT,
    "alice_track_count": $ALICE_TRACK_COUNT,
    "alice_top_track": "$ALICE_TOP_TRACK",
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "csv_rows": $CSV_ROWS,
    "csv_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start": $TASK_START,
    ${GUI_EVIDENCE}
}
EOF

# Move securely
rm -f /tmp/royalty_result.json 2>/dev/null || sudo rm -f /tmp/royalty_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/royalty_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/royalty_result.json
chmod 666 /tmp/royalty_result.json 2>/dev/null || sudo chmod 666 /tmp/royalty_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/royalty_result.json"
cat /tmp/royalty_result.json
echo "=== Export complete ==="