#!/bin/bash
echo "=== Exporting Returns to Schooling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check CSV Result (Model Comparison)
CSV_FILE="$OUTPUT_DIR/wage_analysis_comparison.csv"
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
OLS_EST="0"
IV_EST="0"

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
    
    # Python extraction of values
    VALS=$(python3 -c "
import csv
try:
    with open('$CSV_FILE', 'r') as f:
        reader = csv.DictReader(f)
        ols_val = 0
        iv_val = 0
        for row in reader:
            # Flexible key matching
            model_name = str(row.get('model', '')).lower()
            est = float(row.get('estimate_educ', 0))
            if 'ols' in model_name:
                ols_val = est
            elif 'iv' in model_name or '2sls' in model_name:
                iv_val = est
        print(f'{ols_val},{iv_val}')
except Exception:
    print('0,0')
")
    OLS_EST=$(echo "$VALS" | cut -d',' -f1)
    IV_EST=$(echo "$VALS" | cut -d',' -f2)
fi

# 2. Check Hausman Test Text
TEST_FILE="$OUTPUT_DIR/hausman_test_result.txt"
TEST_EXISTS="false"
TEST_SIGNIFICANT="false"

if [ -f "$TEST_FILE" ]; then
    TEST_EXISTS="true"
    # Check if file content suggests significance (p-value < 0.05 usually)
    # Looking for small p-value scientific notation or small decimal
    if grep -qiE "p-value.*<.*0\.05|p-value.*=.*0\.00|2\.2e-16" "$TEST_FILE"; then
        TEST_SIGNIFICANT="true"
    fi
fi

# 3. Check Plot
PLOT_FILE="$OUTPUT_DIR/first_stage_instrument.png"
PLOT_EXISTS="false"
PLOT_SIZE_KB="0"

if [ -f "$PLOT_FILE" ]; then
    PLOT_EXISTS="true"
    PLOT_SIZE_KB=$(du -k "$PLOT_FILE" | cut -f1)
fi

# 4. Check Script
SCRIPT_FILE="/home/ga/RProjects/returns_to_schooling.R"
SCRIPT_MODIFIED="false"
PACKAGES_INSTALLED="false"

if [ -f "$SCRIPT_FILE" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Check if packages were actually installed in user library
if [ -d "/home/ga/R/library/wooldridge" ] && [ -d "/home/ga/R/library/AER" ]; then
    PACKAGES_INSTALLED="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during": $CSV_CREATED_DURING,
    "ols_estimate": $OLS_EST,
    "iv_estimate": $IV_EST,
    "test_file_exists": $TEST_EXISTS,
    "test_significant": $TEST_SIGNIFICANT,
    "plot_exists": $PLOT_EXISTS,
    "plot_size_kb": $PLOT_SIZE_KB,
    "script_modified": $SCRIPT_MODIFIED,
    "packages_installed": $PACKAGES_INSTALLED,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"