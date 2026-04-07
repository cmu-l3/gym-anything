#!/bin/bash
echo "=== Exporting HSB Multilevel Modeling Results ==="

source /workspace/scripts/task_utils.sh

# Record end state
take_screenshot /tmp/hsb_final.png
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Helper to check file status
check_file() {
    local path="$1"
    local exists="false"
    local is_new="false"
    local size=0

    if [ -f "$path" ]; then
        exists="true"
        size=$(stat -c %s "$path")
        mtime=$(stat -c %Y "$path")
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new="true"
        fi
    fi
    echo "{\"exists\": $exists, \"is_new\": $is_new, \"size\": $size}"
}

# 1. Check R Script
SCRIPT_STATUS=$(check_file "/home/ga/RProjects/hsb_multilevel.R")

# 2. Check Model Comparison CSV
COMP_CSV="$OUTPUT_DIR/hsb_model_comparison.csv"
COMP_STATUS=$(check_file "$COMP_CSV")
COMP_DATA="{}"
if [ -f "$COMP_CSV" ]; then
    # Use python to safely parse CSV and check basic constraints
    COMP_DATA=$(python3 -c "
import csv, json
try:
    with open('$COMP_CSV', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        cols = reader.fieldnames if reader.fieldnames else []
        
        # Check null model ICC (approx 0.18)
        null_icc = 0
        for r in rows:
            if 'null' in str(r.get('model','')).lower() or 'intercept' in str(r.get('model','')).lower() or r.get('icc', ''):
                try: 
                    val = float(r.get('icc', 0))
                    if val > 0: null_icc = val
                except: pass
        
        print(json.dumps({
            'rows': len(rows),
            'cols': cols,
            'has_icc': 'icc' in cols,
            'null_icc_value': null_icc
        }))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
fi

# 3. Check Fixed Effects CSV
FIXED_CSV="$OUTPUT_DIR/hsb_fixed_effects.csv"
FIXED_STATUS=$(check_file "$FIXED_CSV")
FIXED_DATA="{}"
if [ -f "$FIXED_CSV" ]; then
    FIXED_DATA=$(python3 -c "
import csv, json
try:
    with open('$FIXED_CSV', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
        # Check coefficients signs
        checks = {'ses': 0, 'minority': 0, 'sector': 0}
        for r in rows:
            term = r.get('term', '').lower()
            try:
                est = float(r.get('estimate', 0))
                if 'ses' in term and 'mean' not in term: checks['ses'] = est
                if 'minority' in term: checks['minority'] = est
                if 'sector' in term: checks['sector'] = est
            except: pass
            
        print(json.dumps({
            'rows': len(rows),
            'coef_checks': checks
        }))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
fi

# 4. Check Images
CAT_PLOT_STATUS=$(check_file "$OUTPUT_DIR/hsb_caterpillar.png")
SES_PLOT_STATUS=$(check_file "$OUTPUT_DIR/hsb_ses_effects.png")

# Verify RStudio was running
APP_RUNNING=$(pgrep -f "rstudio" > /dev/null && echo "true" || echo "false")

# Compile full result
# Using a temp file to avoid escaping hell
TEMP_JSON=$(mktemp /tmp/hsb_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "script": $SCRIPT_STATUS,
    "comparison_csv": $COMP_STATUS,
    "comparison_data": $COMP_DATA,
    "fixed_csv": $FIXED_STATUS,
    "fixed_data": $FIXED_DATA,
    "caterpillar_plot": $CAT_PLOT_STATUS,
    "ses_plot": $SES_PLOT_STATUS,
    "screenshot_path": "/tmp/hsb_final.png"
}
EOF

# Move to final destination
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"