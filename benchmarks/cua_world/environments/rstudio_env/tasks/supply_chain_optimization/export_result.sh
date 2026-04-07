#!/bin/bash
echo "=== Exporting Supply Chain Optimization Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

take_screenshot /tmp/task_end.png

# Initialize result variables
PLAN_EXISTS="false"
PLAN_IS_NEW="false"
MAP_EXISTS="false"
MAP_IS_NEW="false"
COST_MATRIX_EXISTS="false"
TOTAL_QUANTITY=0

# Check Optimal Plan CSV
PLAN_FILE="$OUTPUT_DIR/optimal_plan.csv"
if [ -f "$PLAN_FILE" ]; then
    PLAN_EXISTS="true"
    MTIME=$(stat -c %Y "$PLAN_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLAN_IS_NEW="true"
    fi
    
    # Simple check: Sum of quantities (should match total demand 3400)
    # Assumes column 'quantity' exists. We try to find it.
    TOTAL_QUANTITY=$(python3 -c "
import csv
try:
    with open('$PLAN_FILE') as f:
        reader = csv.DictReader(f)
        total = 0
        for row in reader:
            # Handle case-insensitive column names
            q_val = 0
            for k, v in row.items():
                if 'quantity' in k.lower() or 'amount' in k.lower() or 'units' in k.lower():
                    try: q_val = float(v)
                    except: pass
                    break
            total += q_val
        print(int(total))
except:
    print(0)
")
fi

# Check Map PNG
MAP_FILE="$OUTPUT_DIR/supply_chain_map.png"
if [ -f "$MAP_FILE" ]; then
    MAP_EXISTS="true"
    MTIME=$(stat -c %Y "$MAP_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        MAP_IS_NEW="true"
    fi
    MAP_SIZE=$(stat -c %s "$MAP_FILE" 2>/dev/null || echo "0")
else
    MAP_SIZE=0
fi

# Check Cost Matrix
MATRIX_FILE="$OUTPUT_DIR/shipping_costs_matrix.csv"
if [ -f "$MATRIX_FILE" ]; then
    COST_MATRIX_EXISTS="true"
fi

# Script check
SCRIPT_FILE="/home/ga/RProjects/optimization_analysis.R"
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_FILE" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "plan_exists": $PLAN_EXISTS,
    "plan_is_new": $PLAN_IS_NEW,
    "map_exists": $MAP_EXISTS,
    "map_is_new": $MAP_IS_NEW,
    "map_size_bytes": $MAP_SIZE,
    "cost_matrix_exists": $COST_MATRIX_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "total_quantity_shipped": $TOTAL_QUANTITY,
    "task_start_timestamp": $TASK_START
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="