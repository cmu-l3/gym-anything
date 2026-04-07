#!/bin/bash
echo "=== Exporting SPC Process Capability Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Load start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CAPABILITY_CSV="/home/ga/RProjects/output/spc_capability.csv"
OOC_CSV="/home/ga/RProjects/output/spc_ooc_points.csv"
CHARTS_PNG="/home/ga/RProjects/output/spc_control_charts.png"
SCRIPT_R="/home/ga/RProjects/spc_analysis.R"

# Initialize Result Variables
CAPABILITY_EXISTS=false
CAPABILITY_VALID=false
CAPABILITY_DATA="{}"
OOC_EXISTS=false
OOC_ROWS=0
PNG_EXISTS=false
PNG_SIZE=0
SCRIPT_EXISTS=false
SCRIPT_MODIFIED=false
SCRIPT_HAS_QCC=false
SCRIPT_HAS_CUSUM=false

# 1. Check Capability CSV
if [ -f "$CAPABILITY_CSV" ]; then
    FILE_MTIME=$(stat -c %Y "$CAPABILITY_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CAPABILITY_EXISTS=true
        
        # Parse CSV to JSON for verification
        # Python script to extract metrics and check structure
        CAPABILITY_DATA=$(python3 << 'PYEOF'
import csv
import json
import sys

results = {}
try:
    with open("/home/ga/RProjects/output/spc_capability.csv", 'r') as f:
        reader = csv.DictReader(f)
        # normalize headers
        headers = [h.lower() for h in reader.fieldnames] if reader.fieldnames else []
        
        # Check if headers contain 'metric' and 'value' roughly
        if not any('metric' in h for h in headers) or not any('value' in h for h in headers):
            print(json.dumps({"error": "Invalid headers"}))
            sys.exit(0)
            
        metric_col = next(h for h in reader.fieldnames if 'metric' in h.lower())
        value_col = next(h for h in reader.fieldnames if 'value' in h.lower())
        
        for row in reader:
            if row[metric_col] and row[value_col]:
                key = row[metric_col].strip()
                try:
                    val = float(row[value_col])
                    results[key] = val
                except ValueError:
                    continue
    print(json.dumps(results))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
        # Check if parsing was successful (look for Cp in keys)
        if echo "$CAPABILITY_DATA" | grep -q "Cp"; then
            CAPABILITY_VALID=true
        fi
    fi
fi

# 2. Check OOC Points CSV
if [ -f "$OOC_CSV" ]; then
    FILE_MTIME=$(stat -c %Y "$OOC_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OOC_EXISTS=true
        OOC_ROWS=$(awk 'END {print NR}' "$OOC_CSV") 
        # Subtract 1 for header if it exists
        OOC_ROWS=$((OOC_ROWS - 1))
        [ $OOC_ROWS -lt 0 ] && OOC_ROWS=0
    fi
fi

# 3. Check Charts PNG
if [ -f "$CHARTS_PNG" ]; then
    FILE_MTIME=$(stat -c %Y "$CHARTS_PNG" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PNG_EXISTS=true
        PNG_SIZE=$(stat -c %s "$CHARTS_PNG")
    fi
fi

# 4. Check R Script
if [ -f "$SCRIPT_R" ]; then
    SCRIPT_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$SCRIPT_R" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED=true
    fi
    
    # Check content
    CONTENT=$(cat "$SCRIPT_R")
    if echo "$CONTENT" | grep -q "qcc"; then
        SCRIPT_HAS_QCC=true
    fi
    if echo "$CONTENT" | grep -qi "cusum"; then
        SCRIPT_HAS_CUSUM=true
    fi
fi

# 5. Check if qcc was actually installed
QCC_INSTALLED=false
if R --slave -e "quit(status=!require('qcc', quietly=TRUE))" 2>/dev/null; then
    QCC_INSTALLED=true
fi

# 6. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "capability_exists": $CAPABILITY_EXISTS,
    "capability_valid": $CAPABILITY_VALID,
    "capability_data": $CAPABILITY_DATA,
    "ooc_exists": $OOC_EXISTS,
    "ooc_rows": $OOC_ROWS,
    "png_exists": $PNG_EXISTS,
    "png_size_bytes": $PNG_SIZE,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "script_has_qcc": $SCRIPT_HAS_QCC,
    "script_has_cusum": $SCRIPT_HAS_CUSUM,
    "qcc_installed": $QCC_INSTALLED,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated:"
cat /tmp/task_result.json

echo "=== Export Complete ==="