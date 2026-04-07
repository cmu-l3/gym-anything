#!/bin/bash
# Export script for Sakila Storage Intelligence Dashboard

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check if views exist
echo "Checking for views..."
VIEWS_CHECK=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT table_name 
    FROM views 
    WHERE table_schema='sakila' 
    AND table_name IN ('v_storage_metrics', 'v_maintenance_required');
" 2>/dev/null)

VIEW_METRICS_EXISTS="false"
VIEW_MAINT_EXISTS="false"

if echo "$VIEWS_CHECK" | grep -q "v_storage_metrics"; then VIEW_METRICS_EXISTS="true"; fi
if echo "$VIEWS_CHECK" | grep -q "v_maintenance_required"; then VIEW_MAINT_EXISTS="true"; fi

# 2. Validate View Logic (Mathematical Correctness)
# We run a query against the user's view and compare it with our own calculation
LOGIC_CORRECT="false"
ZERO_DIV_HANDLED="false"

if [ "$VIEW_METRICS_EXISTS" = "true" ]; then
    # Pick a table to test (e.g., actor)
    # Get raw values from info schema
    RAW_STATS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT data_length, index_length, data_free 
        FROM tables 
        WHERE table_schema='sakila' AND table_name='actor';
    " 2>/dev/null)
    
    D_LEN=$(echo $RAW_STATS | awk '{print $1}')
    I_LEN=$(echo $RAW_STATS | awk '{print $2}')
    D_FREE=$(echo $RAW_STATS | awk '{print $3}')
    
    # Calculate expected values (using python for precision)
    EXPECTED_JSON=$(python3 -c "
try:
    d_len = $D_LEN
    i_len = $I_LEN
    d_free = $D_FREE
    total_mb = round((d_len + i_len) / 1024 / 1024, 2)
    idx_pct = round((i_len / (d_len + i_len)) * 100, 1) if (d_len + i_len) > 0 else 0.0
    frag_pct = round((d_free / d_len) * 100, 1) if d_len > 0 else 0.0
    print(f'{total_mb},{idx_pct},{frag_pct}')
except:
    print('0,0,0')
")
    
    EXP_MB=$(echo $EXPECTED_JSON | cut -d',' -f1)
    EXP_IDX=$(echo $EXPECTED_JSON | cut -d',' -f2)
    EXP_FRAG=$(echo $EXPECTED_JSON | cut -d',' -f3)

    # Get User's values
    USER_VALS=$(mysql -u ga -ppassword123 sakila -N -e "
        SELECT total_size_mb, index_pct, fragmentation_pct 
        FROM v_storage_metrics 
        WHERE table_name='actor';
    " 2>/dev/null)
    
    USR_MB=$(echo $USER_VALS | awk '{print $1}')
    USR_IDX=$(echo $USER_VALS | awk '{print $2}')
    USR_FRAG=$(echo $USER_VALS | awk '{print $3}')

    echo "Logic Check (Actor table):"
    echo "  Expected: MB=$EXP_MB, Idx%=$EXP_IDX, Frag%=$EXP_FRAG"
    echo "  Actual  : MB=$USR_MB, Idx%=$USR_IDX, Frag%=$USR_FRAG"

    # Allow small tolerance for floating point diffs
    if [ -n "$USR_MB" ]; then
        MATCH=$(python3 -c "
try:
    print('true' if abs($USR_MB - $EXP_MB) < 0.02 and abs($USR_IDX - $EXP_IDX) < 0.2 and abs($USR_FRAG - $EXP_FRAG) < 0.2 else 'false')
except:
    print('false')
")
        LOGIC_CORRECT="$MATCH"
    fi

    # Check Zero Division Handling
    # Create a dummy empty table and query it
    mysql -u root -p'GymAnything#2024' sakila -e "CREATE TABLE IF NOT EXISTS zero_test (id INT);" 2>/dev/null
    
    # Analyze to ensure stats are 0
    mysql -u root -p'GymAnything#2024' sakila -e "ANALYZE TABLE zero_test;" 2>/dev/null

    # Query the view for this table
    ZERO_RESULT=$(mysql -u ga -ppassword123 sakila -N -e "SELECT fragmentation_pct FROM v_storage_metrics WHERE table_name='zero_test'" 2>&1)
    
    if [[ "$ZERO_RESULT" != *"ERROR"* ]] && [[ "$ZERO_RESULT" != *"NULL"* ]]; then
        ZERO_DIV_HANDLED="true"
    fi
    
    # Cleanup
    mysql -u root -p'GymAnything#2024' sakila -e "DROP TABLE IF EXISTS zero_test;" 2>/dev/null
fi

# 3. Check CSV Export
CSV_FILE="/home/ga/Documents/exports/maintenance_report.csv"
CSV_EXISTS="false"
CSV_MTIME=0
CSV_CONTENT_VALID="false"
CSV_ROWS=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$(count_csv_lines "$CSV_FILE")
    
    # Check if 'payment' or 'rental' (the fragmented tables) are in the CSV
    CONTENT=$(cat "$CSV_FILE")
    if echo "$CONTENT" | grep -q "payment" || echo "$CONTENT" | grep -q "rental"; then
        CSV_CONTENT_VALID="true"
    fi
fi

# 4. Check Filtering Logic (v_maintenance_required)
FILTER_LOGIC_CORRECT="false"
if [ "$VIEW_MAINT_EXISTS" = "true" ]; then
    # We expect 'payment' and 'rental' to be in this view due to fragmentation created in setup
    ROW_COUNT=$(mysql -u ga -ppassword123 sakila -N -e "
        SELECT COUNT(*) FROM v_maintenance_required 
        WHERE table_name IN ('payment', 'rental');
    " 2>/dev/null)
    
    if [ "$ROW_COUNT" -ge 1 ]; then
        FILTER_LOGIC_CORRECT="true"
    fi
fi

# Generate Result JSON
cat > /tmp/task_result.json << EOF
{
    "view_metrics_exists": $VIEW_METRICS_EXISTS,
    "view_maint_exists": $VIEW_MAINT_EXISTS,
    "logic_correct": $LOGIC_CORRECT,
    "zero_div_handled": $ZERO_DIV_HANDLED,
    "filter_logic_correct": $FILTER_LOGIC_CORRECT,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "csv_content_valid": $CSV_CONTENT_VALID,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="