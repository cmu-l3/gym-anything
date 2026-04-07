#!/bin/bash
echo "=== Exporting Incumbency RDD Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Task Context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_DIR="/home/ga/RProjects/output"

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Verify Files and Extract Data
# We use a python script embedded in bash to safely parse CSVs and check values

PYTHON_PARSER=$(cat << 'PY_EOF'
import json
import os
import csv
import sys

output_dir = "/home/ga/RProjects/output"
task_start = int(sys.argv[1])

results = {
    "mccrary_exists": False,
    "mccrary_new": False,
    "mccrary_size": 0,
    "rdd_plot_exists": False,
    "rdd_plot_new": False,
    "rdd_plot_size": 0,
    "csv_exists": False,
    "csv_new": False,
    "late_value": None,
    "p_value": None
}

# Check McCrary Plot
mccrary_path = os.path.join(output_dir, "mccrary_test.png")
if os.path.exists(mccrary_path):
    results["mccrary_exists"] = True
    results["mccrary_size"] = os.path.getsize(mccrary_path)
    if os.path.getmtime(mccrary_path) > task_start:
        results["mccrary_new"] = True

# Check RDD Plot
plot_path = os.path.join(output_dir, "rdd_plot.png")
if os.path.exists(plot_path):
    results["rdd_plot_exists"] = True
    results["rdd_plot_size"] = os.path.getsize(plot_path)
    if os.path.getmtime(plot_path) > task_start:
        results["rdd_plot_new"] = True

# Check CSV Results
csv_path = os.path.join(output_dir, "rdd_results.csv")
if os.path.exists(csv_path):
    results["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        results["csv_new"] = True
    
    # Parse CSV content
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize column names to lowercase for robustness
            reader.fieldnames = [name.lower() for name in reader.fieldnames] if reader.fieldnames else []
            
            for row in reader:
                # Look for 'late' or 'estimate'
                if 'late' in row:
                    results["late_value"] = float(row['late'])
                elif 'estimate' in row:
                    results["late_value"] = float(row['estimate'])
                
                # Look for 'p_value' or 'p.value' or 'p'
                if 'p_value' in row:
                    results["p_value"] = float(row['p_value'])
                elif 'p.value' in row:
                    results["p_value"] = float(row['p.value'])
                elif 'p' in row:
                    results["p_value"] = float(row['p'])
                break # Only read first row
    except Exception as e:
        results["csv_error"] = str(e)

print(json.dumps(results))
PY_EOF
)

# Execute Python parser
JSON_RESULT=$(python3 -c "$PYTHON_PARSER" "$TASK_START")

# 4. Check if R script was modified
SCRIPT_PATH="/home/ga/RProjects/incumbency_rdd.R"
SCRIPT_MODIFIED="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    # Read content for verification (safe length)
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | head -c 5000)
fi

# 5. Combine everything into final JSON
# We use jq if available, or python to merge
FINAL_JSON=$(python3 -c "
import json
import sys

base_result = json.loads(sys.argv[1])
base_result['task_start'] = $TASK_START
base_result['task_end'] = $TASK_END
base_result['script_modified'] = $SCRIPT_MODIFIED == 'true'
base_result['script_content_snippet'] = sys.argv[2]
base_result['screenshot_path'] = '/tmp/task_final.png'

print(json.dumps(base_result))
" "$JSON_RESULT" "$SCRIPT_CONTENT")

# 6. Save to temp file and copy to safely accessible location
echo "$FINAL_JSON" > /tmp/temp_result.json
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json