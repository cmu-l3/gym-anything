#!/bin/bash
# Export script for dbeaver_export_task_automation
# Verifies file existence, content, and internal DBeaver task configuration

echo "=== Exporting DBeaver Task Result ==="

source /workspace/scripts/task_utils.sh

# Paths
EXPORT_PATH="/home/ga/Documents/exports/top_spenders.csv"
TASKS_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/tasks.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check CSV Output
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_ROW_COUNT=0
CSV_HEADER_VALID="false"
TOP_SPENDER_MATCH="false"

if [ -f "$EXPORT_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Check content
    CSV_ROW_COUNT=$(count_csv_lines "$EXPORT_PATH")
    
    # Check Header
    HEADER=$(head -1 "$EXPORT_PATH" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"customerid"* ]] && [[ "$HEADER" == *"totalspend"* ]]; then
        CSV_HEADER_VALID="true"
    fi
    
    # Check Top Spender (CustomerId 6, Helena Holy, ~49.62)
    # We read the first data row. Assuming sorted descending.
    FIRST_ROW=$(sed -n '2p' "$EXPORT_PATH")
    if echo "$FIRST_ROW" | grep -q "6" && echo "$FIRST_ROW" | grep -q "Holy"; then
        TOP_SPENDER_MATCH="true"
    fi
fi

# 2. Check DBeaver Task Configuration (The "Automation" part)
TASK_CONFIG_EXISTS="false"
TASK_DEFINED="false"
TASK_NAME_MATCH="false"
TASK_TYPE_EXPORT="false"

if [ -f "$TASKS_CONFIG" ]; then
    TASK_CONFIG_EXISTS="true"
    
    # Verify JSON content
    TASK_CHECK=$(python3 -c "
import json
try:
    with open('$TASKS_CONFIG') as f:
        data = json.load(f)
        tasks = data.get('tasks', {})
        found = False
        name_match = False
        type_match = False
        
        for t_id, t_data in tasks.items():
            if t_data.get('label') == 'WeeklyTopSpenders':
                found = True
                name_match = True
                if t_data.get('type') == 'dataExport':
                    type_match = True
                break
        
        print(f'{found}|{name_match}|{type_match}')
except Exception as e:
    print('False|False|False')
" 2>/dev/null)
    
    IFS='|' read -r TASK_DEFINED TASK_NAME_MATCH TASK_TYPE_EXPORT <<< "$TASK_CHECK"
fi

# 3. Check SQL Script
SQL_SCRIPT_EXISTS="false"
# Search in likely locations
if find /home/ga -name "top_customers_query.sql" -newer /tmp/task_start_time.txt | grep -q .; then
    SQL_SCRIPT_EXISTS="true"
fi

# 4. Screenshot
take_screenshot /tmp/task_final.png

# 5. Compile Result
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_header_valid": $CSV_HEADER_VALID,
    "top_spender_match": $TOP_SPENDER_MATCH,
    "task_config_exists": $TASK_CONFIG_EXISTS,
    "task_defined": $TASK_DEFINED,
    "task_name_match": $TASK_NAME_MATCH,
    "task_type_export": $TASK_TYPE_EXPORT,
    "sql_script_exists": $SQL_SCRIPT_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json