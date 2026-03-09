#!/bin/bash
# Export script for northwind_fraud_detection_benford task

echo "=== Exporting Benford Analysis Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
CSV_PATH="/home/ga/Documents/exports/benford_analysis.csv"
SQL_PATH="/home/ga/Documents/scripts/benford_query.sql"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Check Connection
CONNECTION_EXISTS=$(check_dbeaver_connection "Northwind")

# 2. Check SQL Script
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 3. Check CSV Existence and Metadata
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_ROW_COUNT=0
CSV_COLUMNS_VALID="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Check row count (excluding header)
    CSV_ROW_COUNT=$(count_csv_lines "$CSV_PATH")
    
    # Check header columns
    HEADER=$(head -1 "$CSV_PATH" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"digit"* && "$HEADER" == *"count"* && "$HEADER" == *"prop"* ]]; then
        CSV_COLUMNS_VALID="true"
    fi
fi

# 4. Extract CSV Data for Verification
# We output the rows as a JSON object to let Python verifier handle the logic
echo "Extracting CSV data..."
python3 << 'PYEOF'
import csv
import json
import os

csv_path = "/home/ga/Documents/exports/benford_analysis.csv"
data = {}

if os.path.exists(csv_path):
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers
            reader.fieldnames = [h.lower().strip() for h in reader.fieldnames]
            
            for row in reader:
                # Try to find digit column
                digit = None
                for k, v in row.items():
                    if 'digit' in k:
                        digit = v
                        break
                
                # Try to find count column
                count = None
                for k, v in row.items():
                    if 'count' in k and 'expected' not in k and 'benford' not in k:
                        count = v
                        break
                    elif k == 'actualcount' or k == 'count':
                        count = v
                        break
                
                if digit and count:
                    try:
                        d_key = str(int(float(digit))) # handle 1.0 or 1
                        c_val = int(float(count))
                        if d_key in "123456789":
                            data[d_key] = c_val
                    except:
                        pass
    except Exception as e:
        data = {"error": str(e)}

with open('/tmp/agent_csv_data.json', 'w') as f:
    json.dump(data, f)
PYEOF

# Combine everything into result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "sql_exists": $SQL_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_columns_valid": $CSV_COLUMNS_VALID,
    "ground_truth_path": "/tmp/benford_ground_truth.json",
    "agent_data_path": "/tmp/agent_csv_data.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/benford_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/benford_task_result.json
chmod 666 /tmp/benford_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/benford_task_result.json"
echo "=== Export Complete ==="