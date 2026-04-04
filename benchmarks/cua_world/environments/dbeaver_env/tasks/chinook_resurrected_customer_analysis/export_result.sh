#!/bin/bash
# Export script for chinook_resurrected_customer_analysis
# Compares agent output against the ground truth generated in setup

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/exports/resurrected_customers.csv"
SQL_PATH="/home/ga/Documents/scripts/resurrected_analysis.sql"
GROUND_TRUTH_PATH="/tmp/ground_truth.csv"

# 1. Check CSV Existence and Metadata
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
ROW_COUNT=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$CSV_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
    # Count rows excluding header
    ROW_COUNT=$(($(wc -l < "$CSV_PATH") - 1))
fi

# 2. Check SQL Script Existence
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 3. Check DBeaver Connection
# We verify if a connection named 'Chinook' exists in the config
CONNECTION_EXISTS="false"
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "\"name\": \"Chinook\"" "$CONFIG_FILE"; then
        CONNECTION_EXISTS="true"
    fi
fi

# 4. Generate comparison data
# We read the agent's CSV and the ground truth CSV into JSON for the python verifier
# Using a temporary python script to parse CSVs to JSON safely
python3 -c "
import csv
import json
import sys

def csv_to_list(path):
    try:
        with open(path, 'r') as f:
            reader = csv.DictReader(f)
            return [row for row in reader]
    except Exception:
        return []

agent_data = csv_to_list('$CSV_PATH')
gt_data = csv_to_list('$GROUND_TRUTH_PATH')

output = {
    'agent_data': agent_data,
    'ground_truth': gt_data,
    'meta': {
        'csv_exists': '$CSV_EXISTS' == 'true',
        'csv_created_during': '$CSV_CREATED_DURING' == 'true',
        'sql_exists': '$SQL_EXISTS' == 'true',
        'connection_exists': '$CONNECTION_EXISTS' == 'true',
        'row_count': $ROW_COUNT
    }
}
print(json.dumps(output))
" > /tmp/comparison_data.json

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Prepare Final Result JSON
# We embed the comparison data into the result file
cp /tmp/comparison_data.json /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"