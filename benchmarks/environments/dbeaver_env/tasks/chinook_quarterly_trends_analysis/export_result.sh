#!/bin/bash
# Export script for chinook_quarterly_trends_analysis

echo "=== Exporting Quarterly Trends Results ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/quarterly_trends.csv"
SQL_PATH="/home/ga/Documents/scripts/create_trend_view.sql"
GT_FILE="/tmp/trends_ground_truth.json"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database Connection in DBeaver Config
CONNECTION_EXISTS="false"
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q '"name": "Chinook"' "$CONFIG_FILE"; then
        CONNECTION_EXISTS="true"
    fi
fi

# 3. Verify View Existence in Database
VIEW_EXISTS="false"
VIEW_COLUMNS=""
if [ -f "$DB_PATH" ]; then
    # Check sqlite_master for the view
    TYPE_CHECK=$(sqlite3 "$DB_PATH" "SELECT type FROM sqlite_master WHERE name='v_quarterly_analytics';")
    if [ "$TYPE_CHECK" == "view" ]; then
        VIEW_EXISTS="true"
        # Get column names via pragma
        VIEW_COLUMNS=$(sqlite3 "$DB_PATH" "PRAGMA table_info(v_quarterly_analytics);" | cut -d'|' -f2 | tr '\n' ',')
    fi
fi

# 4. Analyze CSV Export
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_CREATED_DURING_TASK="false"
CSV_CONTENT_VALID="false"
CSV_TEST_VALUES="{}"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Count rows (minus header)
    LINE_COUNT=$(wc -l < "$CSV_PATH")
    CSV_ROW_COUNT=$((LINE_COUNT - 1))
    
    # Extract values for the test quarter (2011 Q3) to compare with GT
    # We use python to parse the CSV safely
    CSV_TEST_VALUES=$(python3 << 'PYEOF'
import csv
import json
import sys

csv_file = "/home/ga/Documents/exports/quarterly_trends.csv"
target_year = "2011"
target_qtr = "3"
result = {
    "found": False,
    "revenue": 0,
    "yoy": 0,
    "rolling": 0,
    "columns": []
}

try:
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        result["columns"] = reader.fieldnames
        
        # Normalize headers to lowercase for matching
        headers_map = {h.lower(): h for h in reader.fieldnames}
        
        for row in reader:
            # Find year and quarter columns flexibly
            r_year = row.get(headers_map.get('year', ''), '')
            r_qtr = row.get(headers_map.get('quarter', ''), '')
            
            if str(r_year) == target_year and str(r_qtr) == target_qtr:
                result["found"] = True
                
                # Extract metrics (handle potential formatting like currency symbols)
                rev_key = headers_map.get('quarterlyrevenue', '')
                yoy_key = headers_map.get('yoygrowthpct', '')
                roll_key = headers_map.get('rollingavgrevenue', '')
                
                def clean_float(val):
                    if not val: return 0.0
                    return float(str(val).replace('$','').replace(',','').replace('%',''))

                if rev_key: result["revenue"] = clean_float(row[rev_key])
                if yoy_key: result["yoy"] = clean_float(row[yoy_key])
                if roll_key: result["rolling"] = clean_float(row[roll_key])
                break
                
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
fi

# 5. Check SQL Script
SQL_SCRIPT_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_SCRIPT_EXISTS="true"
fi

# 6. Bundle Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "view_exists": $VIEW_EXISTS,
    "view_columns": "$VIEW_COLUMNS",
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_test_values": $CSV_TEST_VALUES,
    "sql_script_exists": $SQL_SCRIPT_EXISTS,
    "ground_truth": $(cat "$GT_FILE" 2>/dev/null || echo "{}")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="