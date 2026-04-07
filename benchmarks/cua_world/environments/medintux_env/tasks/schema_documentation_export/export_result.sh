#!/bin/bash
echo "=== Exporting Schema Documentation Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/drtuxtest_schema.json"

# 1. Check Output File Status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Generate Ground Truth (to compare against agent's output)
# We generate a mini-JSON of the ACTUAL state of the DB right now
echo "Generating ground truth data..."

python3 -c "
import json
import pymysql
import sys

try:
    conn = pymysql.connect(host='localhost', user='root', password='', database='DrTuxTest', charset='utf8mb4')
    cursor = conn.cursor()
    
    # Get all tables
    cursor.execute(\"SELECT TABLE_NAME, TABLE_ROWS FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='DrTuxTest'\")
    tables = cursor.fetchall()
    table_map = {t[0]: t[1] if t[1] is not None else 0 for t in tables}
    
    # Get top 5 largest
    sorted_tables = sorted(table_map.items(), key=lambda x: x[1], reverse=True)[:5]
    top_5 = [{'name': name, 'row_count': count} for name, count in sorted_tables]
    
    # Get detailed schema for key tables
    key_tables = ['IndexNomPrenom', 'fchpat']
    schemas = {}
    for t_name in key_tables:
        cursor.execute(f\"SELECT COLUMN_NAME, DATA_TYPE, COLUMN_KEY, IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='DrTuxTest' AND TABLE_NAME='{t_name}' ORDER BY ORDINAL_POSITION\")
        cols = cursor.fetchall()
        schemas[t_name] = [{'name': c[0], 'type': c[1], 'key': c[2], 'nullable': c[3]} for c in cols]
        
    ground_truth = {
        'total_tables': len(tables),
        'table_names': list(table_map.keys()),
        'top_5': top_5,
        'schemas': schemas
    }
    
    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(ground_truth, f)
        
except Exception as e:
    print(f'Error generating ground truth: {e}', file=sys.stderr)
    # Fallback empty json
    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump({}, f)
"

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
# We bundle the ground truth AND file stats
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_path": "/tmp/ground_truth.json",
    "agent_output_path": "$OUTPUT_PATH"
}
EOF

# Move result to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"