#!/bin/bash
echo "=== Exporting Wildlife Distance Sampling Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

take_screenshot /tmp/task_end.png

# Initialize result variables
MODEL_CSV_EXISTS="false"
MODEL_CSV_NEW="false"
ABUNDANCE_CSV_EXISTS="false"
ABUNDANCE_CSV_NEW="false"
DETECTION_PNG_EXISTS="false"
QQ_PNG_EXISTS="false"
SCRIPT_EXISTS="false"

# Helper to check file status
check_file() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "true"
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
        echo "false"
    fi
}

# Check files
read MODEL_CSV_EXISTS MODEL_CSV_NEW < <(check_file "$OUTPUT_DIR/model_selection.csv" | xargs)
read ABUNDANCE_CSV_EXISTS ABUNDANCE_CSV_NEW < <(check_file "$OUTPUT_DIR/abundance_estimates.csv" | xargs)
read DETECTION_PNG_EXISTS DETECTION_PNG_NEW < <(check_file "$OUTPUT_DIR/detection_function.png" | xargs)
read QQ_PNG_EXISTS QQ_PNG_NEW < <(check_file "$OUTPUT_DIR/gof_qqplot.png" | xargs)
read SCRIPT_EXISTS SCRIPT_NEW < <(check_file "/home/ga/RProjects/amakihi_analysis.R" | xargs)

# Extract Data from CSVs using inline Python for robustness
# We extract the models and AICs, and the total abundance estimate
EXTRACTION_JSON=$(python3 << 'PYEOF'
import csv
import json
import sys

results = {
    "models": [],
    "best_model_aic": None,
    "abundance_total": 0,
    "regions_count": 0,
    "truncation_suspected": False
}

model_csv = "/home/ga/RProjects/output/model_selection.csv"
abund_csv = "/home/ga/RProjects/output/abundance_estimates.csv"

# Parse Model Selection
try:
    with open(model_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Normalize keys to lowercase
            r = {k.lower().strip(): v for k, v in row.items()}
            
            # Find AIC key
            aic_key = next((k for k in r.keys() if 'aic' in k and 'delta' not in k), None)
            model_key = next((k for k in r.keys() if 'model' in k), None)
            
            if aic_key and model_key:
                try:
                    aic_val = float(r[aic_key])
                    results["models"].append({"name": r[model_key], "aic": aic_val})
                except ValueError:
                    pass
except Exception as e:
    pass

# Parse Abundance
try:
    with open(abund_csv, 'r') as f:
        reader = csv.DictReader(f)
        total_N = 0
        count = 0
        for row in reader:
            # Normalize keys
            r = {k.lower().strip(): v for k, v in row.items()}
            
            # Find Estimate key
            est_key = next((k for k in r.keys() if 'estimate' in k), None)
            
            if est_key:
                try:
                    val = float(r[est_key])
                    # Simple check: Region estimates usually aren't massive, Total is usually separate row
                    # or sum of regions. Let's sum valid numbers.
                    # Some Distance outputs include a "Total" row.
                    lbl_key = next((k for k in r.keys() if 'region' in k or 'label' in k), None)
                    if lbl_key and "total" in str(r[lbl_key]).lower():
                        results["abundance_total_row"] = val
                    else:
                        total_N += val
                        count += 1
                except ValueError:
                    pass
        
        results["abundance_sum"] = total_N
        results["regions_count"] = count
        
        # Use explicit total row if found, otherwise sum
        if "abundance_total_row" in results:
            results["abundance_total"] = results["abundance_total_row"]
        else:
            results["abundance_total"] = results["abundance_sum"]

except Exception as e:
    pass

print(json.dumps(results))
PYEOF
)

# Check if Distance package is installed
DISTANCE_INSTALLED=$(R --vanilla --slave -e "cat(requireNamespace('Distance', quietly=TRUE))" 2>/dev/null)

# Prepare final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "model_csv": {"exists": $MODEL_CSV_EXISTS, "new": $MODEL_CSV_NEW},
        "abundance_csv": {"exists": $ABUNDANCE_CSV_EXISTS, "new": $ABUNDANCE_CSV_NEW},
        "detection_png": {"exists": $DETECTION_PNG_EXISTS, "new": $DETECTION_PNG_NEW},
        "qq_png": {"exists": $QQ_PNG_EXISTS, "new": $QQ_PNG_NEW},
        "script": {"exists": $SCRIPT_EXISTS, "new": $SCRIPT_NEW}
    },
    "data": $EXTRACTION_JSON,
    "env": {
        "distance_package_installed": "$DISTANCE_INSTALLED"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json