#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
JSON_FILE="/home/ga/Documents/SAM_Projects/phoenix_bill_savings.json"
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/bill_savings_analysis.py"

JSON_EXISTS="false"
JSON_MODIFIED="false"
SCRIPT_EXISTS="false"
PYSAM_USED="false"

# Check JSON output file
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Check Python script
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    if grep -ql "import PySAM\|from PySAM" "$SCRIPT_FILE" 2>/dev/null; then
        PYSAM_USED="true"
    fi
fi

# Check bash history for script execution fallback
PYTHON_RAN="false"
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Read values using jq
ANNUAL_ENERGY="0"
BILL_NO_SOLAR="0"
BILL_WITH_SOLAR="0"
SAVINGS="0"
NPV="0"
PAYBACK="0"

if [ "$JSON_EXISTS" = "true" ] && command -v jq &> /dev/null; then
    if jq empty "$JSON_FILE" 2>/dev/null; then
        ANNUAL_ENERGY=$(jq -r '.annual_energy_kwh // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        BILL_NO_SOLAR=$(jq -r '.annual_bill_without_solar_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        BILL_WITH_SOLAR=$(jq -r '.annual_bill_with_solar_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        SAVINGS=$(jq -r '.first_year_savings_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        NPV=$(jq -r '.npv_25yr_dollars // 0' "$JSON_FILE" 2>/dev/null || echo "0")
        PAYBACK=$(jq -r '.simple_payback_years // 0' "$JSON_FILE" 2>/dev/null || echo "0")
    fi
fi

# Ensure floats string output fallback to '0' if 'null'
[ "$ANNUAL_ENERGY" = "null" ] && ANNUAL_ENERGY="0"
[ "$BILL_NO_SOLAR" = "null" ] && BILL_NO_SOLAR="0"
[ "$BILL_WITH_SOLAR" = "null" ] && BILL_WITH_SOLAR="0"
[ "$SAVINGS" = "null" ] && SAVINGS="0"
[ "$NPV" = "null" ] && NPV="0"
[ "$PAYBACK" = "null" ] && PAYBACK="0"

# Build result JSON
jq -n \
    --argjson json_exists "$JSON_EXISTS" \
    --argjson json_modified "$JSON_MODIFIED" \
    --argjson script_exists "$SCRIPT_EXISTS" \
    --argjson pysam_used "$PYSAM_USED" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg bill_no_solar "$BILL_NO_SOLAR" \
    --arg bill_with_solar "$BILL_WITH_SOLAR" \
    --arg savings "$SAVINGS" \
    --arg npv "$NPV" \
    --arg payback "$PAYBACK" \
    '{
        json_exists: $json_exists,
        json_modified: $json_modified,
        script_exists: $script_exists,
        pysam_used: $pysam_used,
        python_ran: $python_ran,
        annual_energy: $annual_energy,
        bill_no_solar: $bill_no_solar,
        bill_with_solar: $bill_with_solar,
        savings: $savings,
        npv: $npv,
        payback: $payback
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="