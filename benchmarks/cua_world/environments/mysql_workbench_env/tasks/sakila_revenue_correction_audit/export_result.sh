#!/bin/bash
# Export script for sakila_revenue_correction_audit task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# --- 1. Verify CSV Export ---
CSV_PATH="/home/ga/Documents/exports/underpayment_audit.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    # Count rows excluding header
    CSV_ROWS=$(tail -n +2 "$CSV_PATH" | wc -l)
fi

# --- 2. Verify View Existence and Logic ---
VIEW_NAME="v_audit_underpayments"
VIEW_EXISTS="false"
VIEW_COLUMNS_VALID="false"

# Check existence
VIEW_CHECK=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='$VIEW_NAME';
")
if [ "$VIEW_CHECK" -gt 0 ]; then
    VIEW_EXISTS="true"
    
    # Check columns
    COLS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT COLUMN_NAME FROM COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='$VIEW_NAME';
    ")
    
    if echo "$COLS" | grep -q "payment_id" && \
       echo "$COLS" | grep -q "amount" && \
       echo "$COLS" | grep -q "rental_rate" && \
       echo "$COLS" | grep -q "difference"; then
        VIEW_COLUMNS_VALID="true"
    fi
fi

# --- 3. Verify Data Correction (The Fix) ---
# Check the specific IDs we corrupted
FIXED_COUNT=0
TOTAL_TARGETS=0
FAILED_IDS=""

if [ -f /tmp/ground_truth_targets.txt ]; then
    TOTAL_TARGETS=$(wc -l < /tmp/ground_truth_targets.txt)
    
    # Read line by line: payment_id rental_rate
    while read -r pid rate; do
        # Get current amount from DB
        CURRENT_AMOUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT amount FROM payment WHERE payment_id = $pid")
        
        # Compare (floating point safe comparison using awk)
        MATCH=$(awk -v cur="$CURRENT_AMOUNT" -v tgt="$rate" 'BEGIN {print (cur == tgt) ? "1" : "0"}')
        
        if [ "$MATCH" -eq 1 ]; then
            FIXED_COUNT=$((FIXED_COUNT + 1))
        else
            FAILED_IDS="$FAILED_IDS $pid($CURRENT_AMOUNT!=$rate)"
        fi
    done < /tmp/ground_truth_targets.txt
fi

# --- 4. Verify Safety (Regression Check) ---
# Check the control group IDs to ensure they weren't changed
SAFETY_VIOLATIONS=0
if [ -f /tmp/ground_truth_control.txt ]; then
    while read -r pid original_amt; do
        CURRENT_AMOUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT amount FROM payment WHERE payment_id = $pid")
        MATCH=$(awk -v cur="$CURRENT_AMOUNT" -v orig="$original_amt" 'BEGIN {print (cur == orig) ? "1" : "0"}')
        
        if [ "$MATCH" -eq 0 ]; then
            SAFETY_VIOLATIONS=$((SAFETY_VIOLATIONS + 1))
        fi
    done < /tmp/ground_truth_control.txt
fi

# Write JSON result
cat > "$RESULT_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_rows": $CSV_ROWS,
    "view_exists": $VIEW_EXISTS,
    "view_columns_valid": $VIEW_COLUMNS_VALID,
    "total_targets": $TOTAL_TARGETS,
    "fixed_count": $FIXED_COUNT,
    "safety_violations": $SAFETY_VIOLATIONS,
    "task_start_time": $TASK_START
}
EOF

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result generated at $RESULT_JSON"
cat "$RESULT_JSON"