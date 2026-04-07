#!/bin/bash
echo "=== Exporting SIR Influenza Modeling Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CSV_PATH="/home/ga/RProjects/output/sir_parameters.csv"
PLOT_PATH="/home/ga/RProjects/output/sir_fit_plot.png"
SCRIPT_PATH="/home/ga/RProjects/sir_analysis.R"

# 1. Check CSV Output
CSV_EXISTS="false"
CSV_NEW="false"
BETA_VAL="0"
GAMMA_VAL="0"
R0_VAL="0"
SSE_VAL="0"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_NEW="true"
    fi
    
    # Extract values using Python for robustness
    VALUES=$(python3 << PYEOF
import csv
import sys

try:
    with open("$CSV_PATH", 'r') as f:
        reader = csv.DictReader(f)
        row = next(reader)
        # Handle case-insensitive keys
        row = {k.lower(): v for k, v in row.items()}
        
        beta = row.get('beta', 0)
        gamma = row.get('gamma', 0)
        r0 = row.get('r0', 0)
        sse = row.get('sse', 0)
        
        print(f"{beta} {gamma} {r0} {sse}")
except Exception:
    print("0 0 0 0")
PYEOF
    )
    BETA_VAL=$(echo "$VALUES" | awk '{print $1}')
    GAMMA_VAL=$(echo "$VALUES" | awk '{print $2}')
    R0_VAL=$(echo "$VALUES" | awk '{print $3}')
    SSE_VAL=$(echo "$VALUES" | awk '{print $4}')
fi

# 2. Check Plot Output
PLOT_EXISTS="false"
PLOT_NEW="false"
PLOT_SIZE=0

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PLOT_NEW="true"
    fi
    PLOT_SIZE=$(stat -c %s "$PLOT_PATH" 2>/dev/null || echo "0")
fi

# 3. Check Script Content
SCRIPT_MODIFIED="false"
USES_DESOLVE="false"
USES_OUTBREAKS="false"

if [ -f "$SCRIPT_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    
    CONTENT=$(cat "$SCRIPT_PATH")
    if echo "$CONTENT" | grep -qi "deSolve"; then
        USES_DESOLVE="true"
    fi
    if echo "$CONTENT" | grep -qi "outbreaks"; then
        USES_OUTBREAKS="true"
    fi
fi

# 4. Check Installed Packages
PACKAGES_INSTALLED="false"
if R --slave -e 'installed.packages()[,"Package"]' 2>/dev/null | grep -q "deSolve"; then
    PACKAGES_INSTALLED="true"
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_NEW,
    "beta": $BETA_VAL,
    "gamma": $GAMMA_VAL,
    "r0": $R0_VAL,
    "sse": $SSE_VAL,
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_NEW,
    "plot_size_bytes": $PLOT_SIZE,
    "script_modified": $SCRIPT_MODIFIED,
    "uses_desolve": $USES_DESOLVE,
    "uses_outbreaks": $USES_OUTBREAKS,
    "packages_installed_check": $PACKAGES_INSTALLED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="