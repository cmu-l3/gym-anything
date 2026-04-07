#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Check if expected file exists
EXPECTED_FILE="/home/ga/Documents/SAM_Projects/merchant_plant_results.json"
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    FILE_MTIME=$(stat -c%Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Extract JSON values safely using jq (fall back to -999 for errors so we can detect parsing issues)
ANNUAL_ENERGY="-999"
CAPACITY_FACTOR="-999"
REVENUE="-999"
NPV="-999"
IRR="-999"
KEYS_MISSING="true"

if [ -f "$EXPECTED_FILE" ] && command -v jq &> /dev/null; then
    if jq empty "$EXPECTED_FILE" 2>/dev/null; then
        # Check if all 5 exact keys are present
        KEY_COUNT=$(jq -r 'keys | map(select(. == "annual_energy_kwh" or . == "capacity_factor_pct" or . == "year1_energy_revenue_dollars" or . == "npv_dollars" or . == "irr_percent")) | length' "$EXPECTED_FILE")
        if [ "$KEY_COUNT" -eq "5" ]; then
            KEYS_MISSING="false"
        fi
        
        ANNUAL_ENERGY=$(jq -r '.annual_energy_kwh // "-999"' "$EXPECTED_FILE" 2>/dev/null)
        CAPACITY_FACTOR=$(jq -r '.capacity_factor_pct // "-999"' "$EXPECTED_FILE" 2>/dev/null)
        REVENUE=$(jq -r '.year1_energy_revenue_dollars // "-999"' "$EXPECTED_FILE" 2>/dev/null)
        NPV=$(jq -r '.npv_dollars // "-999"' "$EXPECTED_FILE" 2>/dev/null)
        IRR=$(jq -r '.irr_percent // "-999"' "$EXPECTED_FILE" 2>/dev/null)
    fi
fi

# Detect Python/PySAM usage for trajectory metadata
PYTHON_RAN="false"
if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
    PYTHON_RAN="true"
fi

# Export structured JSON result to /tmp/task_result.json
jq -n \
    --argjson file_exists "$FILE_EXISTS" \
    --argjson file_modified "$FILE_MODIFIED" \
    --argjson file_size "$FILE_SIZE" \
    --argjson keys_missing "$KEYS_MISSING" \
    --argjson python_ran "$PYTHON_RAN" \
    --arg annual_energy "$ANNUAL_ENERGY" \
    --arg capacity_factor "$CAPACITY_FACTOR" \
    --arg revenue "$REVENUE" \
    --arg npv "$NPV" \
    --arg irr "$IRR" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        file_exists: $file_exists,
        file_modified: $file_modified,
        file_size: $file_size,
        keys_missing: $keys_missing,
        python_ran: $python_ran,
        annual_energy: $annual_energy,
        capacity_factor: $capacity_factor,
        revenue: $revenue,
        npv: $npv,
        irr: $irr,
        timestamp: $timestamp
    }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="