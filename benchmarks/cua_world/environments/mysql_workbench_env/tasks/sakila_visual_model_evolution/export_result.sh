#!/bin/bash
# Export script for sakila_visual_model_evolution task

echo "=== Exporting Visual Model Evolution Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check if the model file exists and was created during the task
MODEL_FILE="/home/ga/Documents/sakila_loyalty_model.mwb"
MODEL_EXISTS="false"
MODEL_MTIME=0

if [ -f "$MODEL_FILE" ]; then
    MODEL_EXISTS="true"
    MODEL_MTIME=$(stat -c%Y "$MODEL_FILE" 2>/dev/null || echo "0")
fi

# 2. Check database state
DB_NAME="sakila"
TABLE_NAME="customer_tier_history"

# Check if table exists
TABLE_EXISTS=$(mysql -u ga -ppassword123 -N -e "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = '$DB_NAME' AND table_name = '$TABLE_NAME';
" 2>/dev/null)
TABLE_EXISTS=${TABLE_EXISTS:-0}

# Check columns
# We expect: history_id, customer_id, old_tier, new_tier, change_date
EXPECTED_COLS=("history_id" "customer_id" "old_tier" "new_tier" "change_date")
MATCHING_COLS=0
MISSING_COLS=""

for col in "${EXPECTED_COLS[@]}"; do
    HAS_COL=$(mysql -u ga -ppassword123 -N -e "
        SELECT COUNT(*) FROM information_schema.columns 
        WHERE table_schema = '$DB_NAME' AND table_name = '$TABLE_NAME' AND column_name = '$col';
    " 2>/dev/null)
    
    if [ "$HAS_COL" -gt 0 ]; then
        MATCHING_COLS=$((MATCHING_COLS + 1))
    else
        MISSING_COLS="$MISSING_COLS $col"
    fi
done

# Check Foreign Key
# Looking for a FK in customer_tier_history that references customer.customer_id
FK_EXISTS=$(mysql -u ga -ppassword123 -N -e "
    SELECT COUNT(*) FROM information_schema.key_column_usage 
    WHERE table_schema = '$DB_NAME' 
      AND table_name = '$TABLE_NAME' 
      AND referenced_table_name = 'customer' 
      AND referenced_column_name = 'customer_id';
" 2>/dev/null)
FK_EXISTS=${FK_EXISTS:-0}

# Generate JSON result
cat > /tmp/model_evolution_result.json << EOF
{
    "task_start": $TASK_START,
    "model_exists": $MODEL_EXISTS,
    "model_mtime": $MODEL_MTIME,
    "table_exists": $TABLE_EXISTS,
    "matching_cols_count": $MATCHING_COLS,
    "missing_cols": "$(echo $MISSING_COLS | xargs)",
    "fk_exists": $FK_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result summary:"
cat /tmp/model_evolution_result.json
echo "=== Export Complete ==="