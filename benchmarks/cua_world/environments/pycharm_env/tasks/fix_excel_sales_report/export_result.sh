#!/bin/bash
echo "=== Exporting Fix Excel Sales Report Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/sales_reporting"
SCRIPT_PATH="$PROJECT_DIR/generate_report.py"
OUTPUT_XLSX="$PROJECT_DIR/weekly_sales_report.xlsx"
DATA_FILE="$PROJECT_DIR/data/transactions.csv"

# 1. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Anti-Gaming: Ensure we test the Agent's CODE, not just a manual file
# We will run the agent's script. If it fails, that's part of the score.
echo "Running agent's script to verify functionality..."

# Remove any existing output to prove the script generates it
rm -f "$OUTPUT_XLSX"

# Run the script
cd "$PROJECT_DIR"
PYTHON_OUTPUT=$(python3 generate_report.py 2>&1)
EXIT_CODE=$?

echo "Script output:"
echo "$PYTHON_OUTPUT"

SCRIPT_RAN_SUCCESSFULLY="false"
if [ $EXIT_CODE -eq 0 ] && [ -f "$OUTPUT_XLSX" ]; then
    SCRIPT_RAN_SUCCESSFULLY="true"
fi

# 3. Export Artifacts for Verification
# We need:
# - The generated Excel file
# - The CSV data (to calculate ground truth)
# - The script content (optional static analysis)

cp "$OUTPUT_XLSX" /tmp/weekly_sales_report.xlsx 2>/dev/null
cp "$DATA_FILE" /tmp/transactions.csv
cp "$SCRIPT_PATH" /tmp/generate_report.py

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "script_exit_code": $EXIT_CODE,
    "script_ran_successfully": $SCRIPT_RAN_SUCCESSFULLY,
    "output_exists": $([ -f "$OUTPUT_XLSX" ] && echo "true" || echo "false"),
    "timestamp": $(date +%s)
}
EOF

# 5. Permission fix for copy_from_env
chmod 666 /tmp/weekly_sales_report.xlsx 2>/dev/null || true
chmod 666 /tmp/transactions.csv 2>/dev/null || true
chmod 666 /tmp/generate_report.py 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="