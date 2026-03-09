#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JASP_FILE="/home/ga/Documents/JASP/Extraversion_BayesianANOVA.jasp"
REPORT_FILE="/home/ga/Documents/JASP/rm_anova_results.txt"
DATASET="/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"

# 1. Check JASP project file
JASP_EXISTS="false"
JASP_CREATED_DURING="false"
JASP_SIZE=0

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# 2. Check Report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Read content safely (limit size)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_FILE")
fi

# 3. Calculate Ground Truth (Highest Mean Item) using Python
# This ensures we verify against the actual data in the environment
echo "Calculating ground truth statistics..."
GROUND_TRUTH_JSON=$(python3 -c "
import csv
import json

try:
    items = ['E1', 'E2', 'E3', 'E4', 'E5']
    sums = {item: 0.0 for item in items}
    counts = {item: 0 for item in items}
    
    with open('$DATASET', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            for item in items:
                if row.get(item):
                    try:
                        val = float(row[item])
                        sums[item] += val
                        counts[item] += 1
                    except ValueError:
                        pass
    
    means = {}
    highest_item = ''
    max_mean = -1.0
    
    for item in items:
        if counts[item] > 0:
            m = sums[item] / counts[item]
            means[item] = m
            if m > max_mean:
                max_mean = m
                highest_item = item
                
    print(json.dumps({
        'status': 'success',
        'means': means,
        'highest_item': highest_item,
        'max_mean': max_mean
    }))
except Exception as e:
    print(json.dumps({'status': 'error', 'error': str(e)}))
" 2>/dev/null || echo '{"status": "failed"}')

# 4. Check if JASP is running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "created_during_task": $JASP_CREATED_DURING,
        "size_bytes": $JASP_SIZE
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING,
        "content": $(echo "$REPORT_CONTENT" | jq -R .)
    },
    "ground_truth": $GROUND_TRUTH_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json