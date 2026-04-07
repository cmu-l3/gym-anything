#!/bin/bash
echo "=== Exporting Bayesian PK Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Define output paths
OUT_DIR="/home/ga/RProjects/output"
SCRIPT_PATH="/home/ga/RProjects/pk_bayesian_analysis.R"

# 4. Helper function to check file status
check_file() {
    local fpath="$1"
    local exists=false
    local is_new=false
    local size=0
    
    if [ -f "$fpath" ]; then
        exists=true
        size=$(stat -c %s "$fpath")
        mtime=$(stat -c %Y "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new=true
        fi
    fi
    echo "$exists|$is_new|$size"
}

# 5. Check all deliverables
IFS='|' read -r PARAMS_EXIST PARAMS_NEW PARAMS_SIZE <<< $(check_file "$OUT_DIR/pk_population_params.csv")
IFS='|' read -r CONV_EXIST CONV_NEW CONV_SIZE <<< $(check_file "$OUT_DIR/pk_convergence.csv")
IFS='|' read -r LOO_EXIST LOO_NEW LOO_SIZE <<< $(check_file "$OUT_DIR/pk_model_comparison.csv")
IFS='|' read -r PPC_EXIST PPC_NEW PPC_SIZE <<< $(check_file "$OUT_DIR/pk_posterior_predictive.png")
IFS='|' read -r FITS_EXIST FITS_NEW FITS_SIZE <<< $(check_file "$OUT_DIR/pk_individual_fits.png")
IFS='|' read -r SCRIPT_EXIST SCRIPT_NEW SCRIPT_SIZE <<< $(check_file "$SCRIPT_PATH")

# 6. Extract key numerical results using Python
# This avoids fragile bash parsing of CSVs
echo "Extracting metrics from CSVs..."
PYTHON_EXTRACT=$(python3 << 'PYEOF'
import csv
import json
import sys

results = {
    "beta_time_est": None,
    "max_rhat": 0.0,
    "loo_models_count": 0,
    "loo_valid": False
}

# 1. Parse Population Params
try:
    with open("/home/ga/RProjects/output/pk_population_params.csv", 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Look for Time coefficient (slope)
            # Row name might be 'Time', 'b_Time', 'beta_Time' etc. depending on package
            param = row.get('parameter', '') or row.get('Parameter', '')
            val = row.get('estimate', '') or row.get('Estimate', '') or row.get('Mean', '')
            
            if 'Time' in param and 'sd' not in param and 'sigma' not in param:
                try: results['beta_time_est'] = float(val)
                except: pass
except: pass

# 2. Parse Convergence
try:
    with open("/home/ga/RProjects/output/pk_convergence.csv", 'r') as f:
        reader = csv.DictReader(f)
        rhats = []
        for row in reader:
            val = row.get('rhat', '') or row.get('Rhat', '')
            try: rhats.append(float(val))
            except: pass
        if rhats:
            results['max_rhat'] = max(rhats)
except: pass

# 3. Parse LOO
try:
    with open("/home/ga/RProjects/output/pk_model_comparison.csv", 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        results['loo_models_count'] = len(rows)
        # Check if we have negative ELPD or LOOIC (valid numbers)
        if len(rows) > 0:
            val = rows[0].get('elpd_loo', '') or rows[0].get('looic', '')
            try: 
                if float(val) != 0: results['loo_valid'] = True
            except: pass
except: pass

print(json.dumps(results))
PYEOF
)

# 7. Analyze script content (simple grep)
HAS_BAYES_PKG=$(grep -E "library\((brms|rstanarm)\)" "$SCRIPT_PATH" 2>/dev/null && echo "true" || echo "false")
HAS_LOO=$(grep "loo(" "$SCRIPT_PATH" 2>/dev/null && echo "true" || echo "false")

# 8. Create result JSON
# Use a temp file to avoid permission issues, then copy
TEMP_JSON=$(mktemp /tmp/pk_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "params_csv": {"exists": $PARAMS_EXIST, "new": $PARAMS_NEW, "size": $PARAMS_SIZE},
        "conv_csv": {"exists": $CONV_EXIST, "new": $CONV_NEW, "size": $CONV_SIZE},
        "loo_csv": {"exists": $LOO_EXIST, "new": $LOO_NEW, "size": $LOO_SIZE},
        "ppc_png": {"exists": $PPC_EXIST, "new": $PPC_NEW, "size": $PPC_SIZE},
        "fits_png": {"exists": $FITS_EXIST, "new": $FITS_NEW, "size": $FITS_SIZE},
        "script": {"exists": $SCRIPT_EXIST, "new": $SCRIPT_NEW, "size": $SCRIPT_SIZE}
    },
    "metrics": $PYTHON_EXTRACT,
    "script_analysis": {
        "has_bayes_pkg": $HAS_BAYES_PKG,
        "has_loo": $HAS_LOO
    }
}
EOF

# Copy to final location (handling permissions if needed)
sudo cp "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json