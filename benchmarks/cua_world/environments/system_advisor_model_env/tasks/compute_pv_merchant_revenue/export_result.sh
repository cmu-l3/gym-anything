#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Check bash history for python
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    PYSAM_FOUND="false"
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$pyf" 2>/dev/null; then
            PYSAM_FOUND="true"
            break
        fi
    done
    if [ "$PYSAM_FOUND" = "true" ]; then
        PYTHON_RAN="true"
    fi
fi

EXPECTED_FILE="/home/ga/Documents/SAM_Projects/merchant_revenue_analysis.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Get expected simple average LMP calculated during setup
EXPECTED_LMP=$(cat /tmp/expected_lmp.txt 2>/dev/null || echo "0")

# Extract JSON values safely
SYSTEM_CAPACITY="0"
ANNUAL_ENERGY="0"
SIMPLE_AVG_LMP="0"
TOTAL_REVENUE="0"
REALIZED_PRICE="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        SYSTEM_CAPACITY=$(jq -r '.system_capacity_kw // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        ANNUAL_ENERGY=$(jq -r '.annual_energy_mwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        SIMPLE_AVG_LMP=$(jq -r '.simple_average_lmp_usd_per_mwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        TOTAL_REVENUE=$(jq -r '.total_merchant_revenue_usd // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        REALIZED_PRICE=$(jq -r '.generation_weighted_realized_price_usd_per_mwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create result JSON
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg expected_lmp "$EXPECTED_LMP" \
    --arg system_capacity "$SYSTEM_CAPACITY" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg simple_avg_lmp "$SIMPLE_AVG_LMP" \
    --arg total_revenue "$TOTAL_REVENUE" \
    --arg realized_price "$REALIZED_PRICE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        python_ran: $python_ran,
        expected_lmp: $expected_lmp,
        system_capacity: $system_capacity,
        annual_energy: $annual_energy,
        simple_avg_lmp: $simple_avg_lmp,
        total_revenue: $total_revenue,
        realized_price: $realized_price,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="