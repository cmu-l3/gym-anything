#!/bin/bash
# Do NOT use set -e
echo "=== Exporting global_health_data_processor task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/health_task_end.png" 2>/dev/null || true

SCRIPT_FILE="/home/ga/Documents/process_health_data.py"
OUTPUT_FILE="/home/ga/Documents/critical_stunting.csv"
TASK_START=$(cat /tmp/global_health_data_start_ts 2>/dev/null || echo "0")

SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MODIFIED="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_FILE" 2>/dev/null || echo "0")
fi

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat --format=%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat --format=%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_MODIFIED="true"
    fi
    
    # Parse output using python
    python3 << 'PYEOF' > /tmp/health_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/health_analysis.json
import json
import csv
import sys

result = {
    "header_correct": False,
    "row_count": 0,
    "has_burundi_top": False,
    "mali_excluded": True,
    "strict_sort": False,
    "error": None
}

try:
    with open("/home/ga/Documents/critical_stunting.csv", "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)
        
        if not rows:
            result["error"] = "empty_file"
            print(json.dumps(result))
            sys.exit(0)
            
        header = rows[0]
        if len(header) == 2 and "country" in header[0].strip().lower() and "percentage" in header[1].strip().lower():
            result["header_correct"] = True
            
        data_rows = rows[1:] if result["header_correct"] else rows
        
        result["row_count"] = len(data_rows)
        
        if data_rows and len(data_rows[0]) >= 2:
            first_country = data_rows[0][0].strip().lower()
            first_val = data_rows[0][1].strip()
            if "burundi" in first_country and ("50.9" in first_val or first_val == "50.9"):
                result["has_burundi_top"] = True
                
        # Check exclusion of Mali or Brazil (should be filtered out since < 30.0)
        for row in data_rows:
            if len(row) > 0:
                country = row[0].strip().lower()
                if "mali" in country or "brazil" in country:
                    result["mali_excluded"] = False
                    
        # Check sorting (descending)
        is_sorted = True
        prev_val = float('inf')
        for row in data_rows:
            if len(row) >= 2:
                try:
                    val = float(row[1].strip())
                    if val > prev_val:
                        is_sorted = False
                        break
                    prev_val = val
                except ValueError:
                    # Ignore invalid floats, but we cannot guarantee sort is correct
                    is_sorted = False
                    break
        
        if data_rows and is_sorted:
            result["strict_sort"] = True
            
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

else:
    echo '{"error":"file_not_found"}' > /tmp/health_analysis.json
fi

# Extract JSON variables
HEADER_CORRECT=$(python3 -c "import json; d=json.load(open('/tmp/health_analysis.json')); print(str(d.get('header_correct',False)).lower())" 2>/dev/null || echo "false")
ROW_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/health_analysis.json')); print(d.get('row_count',0))" 2>/dev/null || echo "0")
HAS_BURUNDI_TOP=$(python3 -c "import json; d=json.load(open('/tmp/health_analysis.json')); print(str(d.get('has_burundi_top',False)).lower())" 2>/dev/null || echo "false")
MALI_EXCLUDED=$(python3 -c "import json; d=json.load(open('/tmp/health_analysis.json')); print(str(d.get('mali_excluded',False)).lower())" 2>/dev/null || echo "false")
STRICT_SORT=$(python3 -c "import json; d=json.load(open('/tmp/health_analysis.json')); print(str(d.get('strict_sort',False)).lower())" 2>/dev/null || echo "false")
ERROR_MSG=$(python3 -c "import json; d=json.load(open('/tmp/health_analysis.json')); print(d.get('error','None'))" 2>/dev/null || echo "None")

cat > /tmp/health_data_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "output_modified": $OUTPUT_MODIFIED,
    "header_correct": $HEADER_CORRECT,
    "row_count": $ROW_COUNT,
    "has_burundi_top": $HAS_BURUNDI_TOP,
    "mali_excluded": $MALI_EXCLUDED,
    "strict_sort": $STRICT_SORT,
    "error_msg": "$ERROR_MSG"
}
EOF

chmod 666 /tmp/health_data_result.json
echo "Result saved to /tmp/health_data_result.json"
cat /tmp/health_data_result.json
echo "=== Export complete ==="