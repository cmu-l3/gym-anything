#!/bin/bash
echo "=== Exporting Surgical Scheduling Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

# Initialize metric variables
DBL_TABLE_EXISTS=false
DBL_ROWS=0
DBL_ROOM_OVERLAP_CORRECT=false
DBL_SURGEON_OVERLAP_CORRECT=false
DBL_BOTH_OVERLAP_CORRECT=false

PROC_EXISTS=false
PROC_PREVENTS_OVERLAP=false
PROC_ALLOWS_CLEAN=false

VIEW_EXISTS=false
VIEW_MERGES_CORRECTLY=false

CSV_EXISTS=false
CSV_SIZE=0

# --- 1. Check DOUBLE_BOOKINGS_LOG Table ---
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner='HOSP_ADMIN' AND table_name='DOUBLE_BOOKINGS_LOG';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DBL_TABLE_EXISTS=true
    DBL_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM hosp_admin.double_bookings_log;" "system" | tr -d '[:space:]')
    
    # Check specific overlap calculations
    ROOM_O=$(oracle_query_raw "SELECT overlap_minutes FROM hosp_admin.double_bookings_log WHERE conflict1_id=1 AND conflict2_id=2;" "system" | tr -d '[:space:]')
    if [ "${ROOM_O:-0}" = "60" ]; then DBL_ROOM_OVERLAP_CORRECT=true; fi

    SURG_O=$(oracle_query_raw "SELECT overlap_minutes FROM hosp_admin.double_bookings_log WHERE conflict1_id=3 AND conflict2_id=4;" "system" | tr -d '[:space:]')
    if [ "${SURG_O:-0}" = "30" ]; then DBL_SURGEON_OVERLAP_CORRECT=true; fi

    BOTH_O=$(oracle_query_raw "SELECT overlap_minutes FROM hosp_admin.double_bookings_log WHERE conflict1_id=7 AND conflict2_id=8;" "system" | tr -d '[:space:]')
    if [ "${BOTH_O:-0}" = "60" ]; then DBL_BOTH_OVERLAP_CORRECT=true; fi
fi

# --- 2. Check PROC_SCHEDULE_SURGERY API ---
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner='HOSP_ADMIN' AND object_name='PROC_SCHEDULE_SURGERY';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
    
    # Test 1: Intentional overlap (Room 1, overlaps with S1 08:00-10:00)
    PROC_FAIL_TEST=$(oracle_query_raw "
    BEGIN
      PROC_SCHEDULE_SURGERY(1, 99, 999, 'Test Failure', TO_DATE('2024-10-01 07:30', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 08:30', 'YYYY-MM-DD HH24:MI'));
    END;
    /" "hosp_admin" "HospAdmin2024" 2>&1)
    
    if echo "$PROC_FAIL_TEST" | grep -q "ORA-20001"; then
        PROC_PREVENTS_OVERLAP=true
    fi

    # Test 2: Clean record insertion
    PROC_SUCC_TEST=$(oracle_query_raw "
    BEGIN
      PROC_SCHEDULE_SURGERY(1, 99, 999, 'Test Success', TO_DATE('2024-10-01 20:00', 'YYYY-MM-DD HH24:MI'), TO_DATE('2024-10-01 22:00', 'YYYY-MM-DD HH24:MI'));
    END;
    /" "hosp_admin" "HospAdmin2024" 2>&1)

    if ! echo "$PROC_SUCC_TEST" | grep -q "ORA-"; then
        # Verify it was inserted
        CLEAN_INS=$(oracle_query_raw "SELECT COUNT(*) FROM hosp_admin.surgery_schedule WHERE procedure_name='Test Success';" "system" | tr -d '[:space:]')
        if [ "${CLEAN_INS:-0}" -gt 0 ] 2>/dev/null; then
            PROC_ALLOWS_CLEAN=true
        fi
    fi
fi

# --- 3. Check ROOM_UTILIZATION_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='HOSP_ADMIN' AND view_name='ROOM_UTILIZATION_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VIEW_EXISTS=true
    
    # Check if Room 1 on 2024-10-01 merged correctly. 
    # S1 (08-10) and S2 (09-11) should equal 180 minutes, NOT 240.
    ROOM1_UTIL=$(oracle_query_raw "SELECT utilized_minutes FROM hosp_admin.room_utilization_vw WHERE room_id=1 AND operation_date=TO_DATE('2024-10-01','YYYY-MM-DD');" "system" | tr -d '[:space:]')
    
    if [ "${ROOM1_UTIL:-0}" = "180" ]; then
        VIEW_MERGES_CORRECTLY=true
    fi
fi

# --- 4. Check CSV Export ---
CSV_PATH="/home/ga/Documents/exports/or_utilization.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# --- 5. GUI Evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON Results
TEMP_JSON=$(mktemp /tmp/surgical_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dbl_table_exists": $DBL_TABLE_EXISTS,
    "dbl_rows": ${DBL_ROWS:-0},
    "dbl_room_overlap_correct": $DBL_ROOM_OVERLAP_CORRECT,
    "dbl_surgeon_overlap_correct": $DBL_SURGEON_OVERLAP_CORRECT,
    "dbl_both_overlap_correct": $DBL_BOTH_OVERLAP_CORRECT,
    "proc_exists": $PROC_EXISTS,
    "proc_prevents_overlap": $PROC_PREVENTS_OVERLAP,
    "proc_allows_clean": $PROC_ALLOWS_CLEAN,
    "view_exists": $VIEW_EXISTS,
    "view_merges_correctly": $VIEW_MERGES_CORRECTLY,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="