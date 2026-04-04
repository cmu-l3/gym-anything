#!/bin/bash
set -e
echo "=== Exporting quantile_regression_food results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Collect Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_FILE="/home/ga/Documents/gretl_output/quantreg_results.txt"
SUMMARY_FILE="/home/ga/Documents/gretl_output/quantreg_summary.txt"

# 3. Check Files Existence and Timestamps (Anti-Gaming)
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false" # Existed but not modified during task
        fi
    else
        echo "missing"
    fi
}

RESULTS_STATUS=$(check_file "$RESULTS_FILE")
SUMMARY_STATUS=$(check_file "$SUMMARY_FILE")

# 4. Generate Ground Truth using gretlcli
# We run the actual analysis in the background to get the exact numbers 
# for the installed version of gretl and this specific dataset.
echo "Generating ground truth..."
GT_LOG="/tmp/ground_truth.log"

# Run batch script to estimate models
# Note: 'const' is automatically added in some versions, but explicit is safer
su - ga -c "gretlcli -b - << EOF > $GT_LOG 2>&1
open /home/ga/Documents/gretl_data/food.gdt
print \"---TAU=0.25---\"
quantreg 0.25 food_exp const income
print \"---TAU=0.50---\"
quantreg 0.50 food_exp const income
print \"---TAU=0.75---\"
quantreg 0.75 food_exp const income
EOF"

# Extract coefficients from log
# Helper to extract income coefficient after a specific marker
get_coeff() {
    local marker="$1"
    # Find the marker, look at following lines for 'income', print the first number
    sed -n "/$marker/,/---TAU/p" "$GT_LOG" | grep -E "^\s*income" | head -1 | awk '{print $2}'
}

GT_025=$(get_coeff "---TAU=0.25---")
GT_050=$(get_coeff "---TAU=0.50---")
GT_075=$(get_coeff "---TAU=0.75---")

# Fallback values if extraction fails (based on POE5 food.gdt standard values)
[ -z "$GT_025" ] && GT_025="7.38"
[ -z "$GT_050" ] && GT_050="10.21"
[ -z "$GT_075" ] && GT_075="11.58"

echo "Ground Truth Coefficients: 0.25=$GT_025, 0.50=$GT_050, 0.75=$GT_075"

# Determine which quantile has the largest slope
LARGEST_TAU="0.75"
MAX_VAL=$GT_075

if (( $(echo "$GT_025 > $MAX_VAL" | bc -l) )); then
    LARGEST_TAU="0.25"
    MAX_VAL=$GT_025
fi
if (( $(echo "$GT_050 > $MAX_VAL" | bc -l) )); then
    LARGEST_TAU="0.50"
    MAX_VAL=$GT_050
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "results_file_status": "$RESULTS_STATUS",
    "summary_file_status": "$SUMMARY_STATUS",
    "ground_truth": {
        "coeff_025": $GT_025,
        "coeff_050": $GT_050,
        "coeff_075": $GT_075,
        "largest_tau": "$LARGEST_TAU"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"