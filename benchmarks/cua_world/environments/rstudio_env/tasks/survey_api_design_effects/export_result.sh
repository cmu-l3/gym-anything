#!/bin/bash
echo "=== Exporting Survey Analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# File paths
ESTIMATES_CSV="$OUTPUT_DIR/api_survey_estimates.csv"
DEFF_CSV="$OUTPUT_DIR/api_design_effects.csv"
REG_CSV="$OUTPUT_DIR/api_regression.csv"
PLOT_PNG="$OUTPUT_DIR/api_survey_analysis.png"
SCRIPT_PATH="/home/ga/RProjects/api_analysis.R"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check File Existence and Freshness ---
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "new"
        else
            echo "old"
        fi
    else
        echo "missing"
    fi
}

EST_STATUS=$(check_file "$ESTIMATES_CSV")
DEFF_STATUS=$(check_file "$DEFF_CSV")
REG_STATUS=$(check_file "$REG_CSV")
PLOT_STATUS=$(check_file "$PLOT_PNG")
SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")

# --- Python Validation of Content ---
# We use an embedded Python script to parse the CSVs and extract values for the verifier
# This avoids complex bash parsing and allows range checking
PYTHON_RESULT=$(python3 << PYEOF
import csv
import json
import sys
import os

results = {
    "estimates": {"valid": False, "strat_elem_mean": 0, "clus_elem_se": 0, "strat_elem_se": 0},
    "deff": {"valid": False, "strat_deff": 0, "clus_deff": 0},
    "regression": {"valid": False, "meals_coef": 0, "meals_p": 1.0},
    "plot_size_kb": 0
}

# 1. Validate Estimates CSV
est_path = "$ESTIMATES_CSV"
if os.path.exists(est_path):
    try:
        with open(est_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Normalize headers
            if rows:
                keys = [k.lower() for k in rows[0].keys()]
                if all(x in keys for x in ['design', 'mean']):
                    results['estimates']['valid'] = True
                    
                    for row in rows:
                        # Handle case-insensitive keys
                        r = {k.lower(): v for k, v in row.items()}
                        design = r.get('design', '').lower()
                        stype = r.get('school_type', r.get('stype', '')).lower()
                        # Get mean column (could be mean_api00, mean, etc)
                        mean_val = float(r.get('mean_api00', r.get('mean', 0)))
                        se_val = float(r.get('se', r.get('std_error', 0)))
                        
                        if 'strat' in design and ('e' == stype or 'elem' in stype):
                            results['estimates']['strat_elem_mean'] = mean_val
                            results['estimates']['strat_elem_se'] = se_val
                        if 'clus' in design and ('e' == stype or 'elem' in stype):
                            results['estimates']['clus_elem_se'] = se_val
    except Exception as e:
        results['estimates']['error'] = str(e)

# 2. Validate DEFF CSV
deff_path = "$DEFF_CSV"
if os.path.exists(deff_path):
    try:
        with open(deff_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if rows:
                results['deff']['valid'] = True
                for row in rows:
                    r = {k.lower(): v for k, v in row.items()}
                    design = r.get('design', '').lower()
                    deff = float(r.get('deff', 0))
                    
                    if 'strat' in design:
                        results['deff']['strat_deff'] = deff
                    if 'clus' in design:
                        results['deff']['clus_deff'] = deff
    except Exception as e:
        results['deff']['error'] = str(e)

# 3. Validate Regression CSV
reg_path = "$REG_CSV"
if os.path.exists(reg_path):
    try:
        with open(reg_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if rows:
                results['regression']['valid'] = True
                for row in rows:
                    r = {k.lower(): v for k, v in row.items()}
                    term = r.get('term', '').lower()
                    if 'meals' in term:
                        results['regression']['meals_coef'] = float(r.get('estimate', 0))
                        results['regression']['meals_p'] = float(r.get('p_value', r.get('p.value', 1.0)))
    except Exception as e:
        results['regression']['error'] = str(e)

# 4. Plot Size
plot_path = "$PLOT_PNG"
if os.path.exists(plot_path):
    results['plot_size_kb'] = os.path.getsize(plot_path) / 1024

print(json.dumps(results))
PYEOF
)

# --- Script Content Check ---
# Check if survey package functions are used
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH")
    HAS_SVYDESIGN=$(echo "$SCRIPT_CONTENT" | grep -c "svydesign")
    HAS_SVYGLM=$(echo "$SCRIPT_CONTENT" | grep -c "svyglm")
else
    HAS_SVYDESIGN=0
    HAS_SVYGLM=0
fi

# Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "estimates_csv": "$EST_STATUS",
        "deff_csv": "$DEFF_STATUS",
        "regression_csv": "$REG_STATUS",
        "plot_png": "$PLOT_STATUS",
        "script": "$SCRIPT_STATUS"
    },
    "script_analysis": {
        "has_svydesign": $HAS_SVYDESIGN,
        "has_svyglm": $HAS_SVYGLM
    },
    "data_validation": $PYTHON_RESULT
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="