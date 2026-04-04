#!/bin/bash
# export_result.sh — Verify the export_feed_csv task

source /workspace/scripts/task_utils.sh

echo "=== Exporting export_feed_csv results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
EXPECTED_FILE="/home/ga/exports/solar_data.csv"

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# Gather file statistics
# -----------------------------------------------------------------------
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
ROW_COUNT=0
VALID_CSV="false"
HAS_HEADER="false"
DATA_PLAUSIBILITY="unknown"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_FILE")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check content
    if [ "$FILE_SIZE" -gt 10 ]; then
        # Count rows (excluding empty lines)
        ROW_COUNT=$(grep -cve '^\s*$' "$EXPECTED_FILE")
        
        # Check CSV validity and plausibility using Python
        # We output a JSON snippet to be merged
        PYTHON_ANALYSIS=$(python3 << 'PYEOF'
import csv
import json
import sys

filename = "/home/ga/exports/solar_data.csv"
result = {
    "valid_csv": False,
    "has_header": False,
    "plausibility": "failed_parse",
    "avg_value": 0,
    "zeros_present": False,
    "max_value": 0
}

try:
    with open(filename, 'r') as f:
        # Read a sample to sniff dialect
        sample = f.read(1024)
        f.seek(0)
        dialect = csv.Sniffer().sniff(sample)
        has_header = csv.Sniffer().has_header(sample)
        result["has_header"] = has_header
        
        reader = csv.reader(f, dialect)
        data = list(reader)
        
        if len(data) > 0:
            result["valid_csv"] = True
            
            # Extract numerical values
            values = []
            start_idx = 1 if has_header else 0
            
            for row in data[start_idx:]:
                if len(row) >= 2:
                    try:
                        # Assuming 2nd column is value, or last column
                        val = float(row[-1]) 
                        values.append(val)
                    except ValueError:
                        pass
            
            if values:
                avg = sum(values) / len(values)
                mx = max(values)
                zeros = any(v == 0 for v in values)
                
                result["avg_value"] = avg
                result["max_value"] = mx
                result["zeros_present"] = zeros
                
                if mx > 0 and mx < 50000: # Reasonable solar watts
                    result["plausibility"] = "plausible"
                else:
                    result["plausibility"] = "implausible_range"
            else:
                 result["plausibility"] = "no_numeric_data"
                 
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
    fi
fi

# -----------------------------------------------------------------------
# Create result JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "row_count": $ROW_COUNT,
    "csv_analysis": ${PYTHON_ANALYSIS:-"{}"},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="