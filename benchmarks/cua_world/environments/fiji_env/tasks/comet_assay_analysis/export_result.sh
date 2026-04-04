#!/bin/bash
echo "=== Exporting Comet Assay Results ==="

# Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/comet"
CSV_FILE="$RESULTS_DIR/comet_analysis.csv"
PNG_FILE="$RESULTS_DIR/roi_overlay.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON fields
CSV_EXISTS="false"
PNG_EXISTS="false"
CSV_VALID="false"
ROW_COUNT=0
MATH_CONSISTENT="false"

# Check CSV
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    # Check modification time
    FILE_TIME=$(stat -c %Y "$CSV_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        # Parse CSV to check validity and row count
        # We use python to parse and check math consistency
        PARSE_RESULT=$(python3 -c "
import csv
import sys

try:
    with open('$CSV_FILE', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        print(len(rows))
        
        # Check math consistency for first row
        if len(rows) > 0:
            r = rows[0]
            # Normalize keys to handle case sensitivity/spaces
            r = {k.strip().lower(): v for k, v in r.items()}
            
            # Find columns
            whole_key = next((k for k in r if 'whole' in k), None)
            head_key = next((k for k in r if 'head' in k), None)
            tail_key = next((k for k in r if 'tail' in k or 'percent' in k), None)
            
            if whole_key and head_key and tail_key:
                w = float(r[whole_key])
                h = float(r[head_key])
                t = float(r[tail_key])
                
                # Check calculation: (W-H)/W*100 vs T
                # Allow 1% tolerance
                calc = (w - h) / w * 100
                if abs(calc - t) < 1.0:
                    print('MATH_OK')
                else:
                    print('MATH_FAIL')
            else:
                print('COLS_MISSING')
        else:
            print('NO_DATA')
except Exception as e:
    print('ERROR')
")
        ROW_COUNT=$(echo "$PARSE_RESULT" | head -n 1)
        MATH_STATUS=$(echo "$PARSE_RESULT" | tail -n 1)
        
        if [ "$ROW_COUNT" -gt 0 ]; then
            CSV_VALID="true"
        fi
        
        if [ "$MATH_STATUS" == "MATH_OK" ]; then
            MATH_CONSISTENT="true"
        fi
    fi
fi

# Check PNG
if [ -f "$PNG_FILE" ]; then
    FILE_TIME=$(stat -c %Y "$PNG_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        PNG_EXISTS="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "png_exists": $PNG_EXISTS,
    "row_count": $ROW_COUNT,
    "math_consistent": $MATH_CONSISTENT,
    "task_start": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json