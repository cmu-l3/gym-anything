#!/bin/bash
echo "=== Exporting Fractal Analysis Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

CSV_PATH="/home/ga/Fiji_Data/results/fractal/fractal_results.csv"
PLOT_PATH="/home/ga/Fiji_Data/results/fractal/fractal_plot.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check CSV
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
PARSED_D_VALUE="0.0"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Attempt to parse D value from CSV
    # Fiji Result tables often have headers. Look for "D" column or just take the likely float value.
    # Typical header: "Counts", "D", "R^2"
    # Or just values if saved without headers.
    PARSED_D_VALUE=$(python3 -c "
import csv, sys
try:
    with open('$CSV_PATH', 'r') as f:
        content = f.read()
        # Handle flexible delimiters (comma or tab)
        delimiter = ',' if ',' in content else '\t'
        reader = csv.DictReader(content.splitlines(), delimiter=delimiter)
        
        # Normalize headers to find 'D'
        d_val = 0.0
        found = False
        
        # Check if headers exist
        if reader.fieldnames:
            # Look for exact 'D' or 'Dimension'
            for row in reader:
                for k, v in row.items():
                    if k and k.strip() == 'D':
                        d_val = float(v)
                        found = True
                        break
                if found: break
        
        # Fallback: if no headers or 'D' not found, look for 2nd or 3rd column in a row of floats
        if not found:
             # Reset file read
             lines = content.splitlines()
             for line in lines:
                 parts = line.replace(',', ' ').replace('\t', ' ').split()
                 # Look for a value between 1.0 and 2.0 which is typical for D of blobs
                 for p in parts:
                     try:
                         val = float(p)
                         if 1.0 < val < 2.0:
                             d_val = val
                             found = True
                             break
                     except:
                         continue
                 if found: break
                 
        print(d_val)
except Exception as e:
    print('0.0')
" 2>/dev/null || echo "0.0")
fi

# Check Plot
PLOT_EXISTS="false"
PLOT_CREATED_DURING_TASK="false"
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED_DURING_TASK="true"
    fi
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/fractal_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED_DURING_TASK,
    "parsed_d_value": $PARSED_D_VALUE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location for retrieval
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="