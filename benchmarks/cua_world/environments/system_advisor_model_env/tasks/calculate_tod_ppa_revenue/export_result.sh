#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Anti-bypass: Check if Python was actually used during the task
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check script creation
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/calculate_tod.py"
SCRIPT_EXISTS="false"
PYSAM_USED="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    PYTHON_RAN="true"
    if grep -ql "import PySAM\|from PySAM\|import Pvwatts\|Pvwattsv" "$SCRIPT_FILE" 2>/dev/null; then
        PYSAM_USED="true"
    fi
fi

# Check expected JSON file
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/tod_revenue_analysis.json"
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract parameters using flexible key paths
TOTAL_GEN_MWH="0"
TOTAL_REVENUE="0"
EFFECTIVE_PRICE="0"
SUMMER_PEAK_REVENUE="0"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        TOTAL_GEN_MWH=$(jq -r '.total_generation_mwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        TOTAL_REVENUE=$(jq -r '.total_revenue_usd // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        EFFECTIVE_PRICE=$(jq -r '.effective_ppa_price_usd_per_mwh // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
        SUMMER_PEAK_REVENUE=$(jq -r '.summer_peak_revenue_usd // 0' "$EXPECTED_FILE" 2>/dev/null || echo "0")
    fi
fi

# Create JSON result safely using jq
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson python_ran "$PYTHON_RAN" \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson pysam_used "$PYSAM_USED" \
    --arg total_gen_mwh "$TOTAL_GEN_MWH" \
    --arg total_revenue "$TOTAL_REVENUE" \
    --arg effective_price "$EFFECTIVE_PRICE" \
    --arg summer_peak_revenue "$SUMMER_PEAK_REVENUE" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        python_ran: $python_ran,
        script_exists: $script_exists,
        pysam_used: $pysam_used,
        total_generation_mwh: $total_gen_mwh,
        total_revenue_usd: $total_revenue,
        effective_ppa_price_usd_per_mwh: $effective_price,
        summer_peak_revenue_usd: $summer_peak_revenue,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="