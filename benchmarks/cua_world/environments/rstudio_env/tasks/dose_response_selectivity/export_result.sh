#!/bin/bash
echo "=== Exporting Dose-Response Task Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for JSON output
json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# 1. Capture Final State
take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
NOW=$(date +%s)

# Paths
RYE_CSV="/home/ga/RProjects/output/ryegrass_model_comparison.csv"
ALBA_CSV="/home/ga/RProjects/output/alba_selectivity.csv"
PLOT_PNG="/home/ga/RProjects/output/dose_response_plots.png"
SCRIPT_R="/home/ga/RProjects/dose_response_analysis.R"

# 2. Check Ryegrass CSV
RYE_EXISTS=false
RYE_IS_NEW=false
RYE_MODEL_COUNT=0
RYE_HAS_COLS=false
RYE_ED50_VALID=false

if [ -f "$RYE_CSV" ]; then
    RYE_EXISTS=true
    MTIME=$(stat -c %Y "$RYE_CSV")
    [ "$MTIME" -gt "$TASK_START" ] && RYE_IS_NEW=true
    
    # Analyze content with Python
    PY_RYE=$(python3 -c "
import pandas as pd
import sys
try:
    df = pd.read_csv('$RYE_CSV')
    cols = [c.lower() for c in df.columns]
    has_cols = all(x in cols for x in ['model', 'aic', 'ed50'])
    
    # Check model count (looking for at least 3 models)
    model_count = len(df)
    
    # Check ED50 validity (mean ED50 roughly around 3.05 for Ryegrass)
    # Accepting range 1.0 to 10.0 to be safe
    valid_ed50 = False
    if 'ed50' in [c.lower() for c in df.columns]:
        # Find the actual column name case-insensitively
        col_name = next(c for c in df.columns if c.lower() == 'ed50')
        vals = pd.to_numeric(df[col_name], errors='coerce').dropna()
        if len(vals) > 0:
            avg = vals.mean()
            if 1.0 <= avg <= 10.0:
                valid_ed50 = True
                
    print(f'{has_cols}|{model_count}|{valid_ed50}')
except Exception as e:
    print('False|0|False')
")
    RYE_HAS_COLS=$(echo "$PY_RYE" | cut -d'|' -f1)
    RYE_MODEL_COUNT=$(echo "$PY_RYE" | cut -d'|' -f2)
    RYE_ED50_VALID=$(echo "$PY_RYE" | cut -d'|' -f3)
fi

# 3. Check Selectivity CSV
ALBA_EXISTS=false
ALBA_IS_NEW=false
ALBA_HAS_HERBS=false
ALBA_SI_VALID=false

if [ -f "$ALBA_CSV" ]; then
    ALBA_EXISTS=true
    MTIME=$(stat -c %Y "$ALBA_CSV")
    [ "$MTIME" -gt "$TASK_START" ] && ALBA_IS_NEW=true
    
    PY_ALBA=$(python3 -c "
import pandas as pd
try:
    df = pd.read_csv('$ALBA_CSV')
    # Check if we have Glyphosate and Bentazone
    # Search in all string columns
    content = df.to_string().lower()
    has_herbs = 'glyphosate' in content and 'bentazone' in content
    
    # Check Selectivity Index logic (Glyphosate ED50 > Bentazone ED50)
    # SI = ED50(Gly) / ED50(Ben) > 1
    si_valid = False
    
    # Try to parse ED50s if structure is row-based
    # Assuming column 'herbicide' and 'ED50'
    cols = [c.lower() for c in df.columns]
    if 'herbicide' in cols and 'ed50' in cols:
        h_col = next(c for c in df.columns if c.lower() == 'herbicide')
        e_col = next(c for c in df.columns if c.lower() == 'ed50')
        
        gly = df[df[h_col].str.contains('Glyphosate', case=False, na=False)][e_col].mean()
        ben = df[df[h_col].str.contains('Bentazone', case=False, na=False)][e_col].mean()
        
        if gly > ben and ben > 0:
            si_valid = True
            
    print(f'{has_herbs}|{si_valid}')
except:
    print('False|False')
")
    ALBA_HAS_HERBS=$(echo "$PY_ALBA" | cut -d'|' -f1)
    ALBA_SI_VALID=$(echo "$PY_ALBA" | cut -d'|' -f2)
fi

# 4. Check Plot
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_KB=0
if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    MTIME=$(stat -c %Y "$PLOT_PNG")
    [ "$MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE_KB=$(du -k "$PLOT_PNG" | cut -f1)
fi

# 5. Check Script
SCRIPT_MODIFIED=false
SCRIPT_HAS_DRC=false
if [ -f "$SCRIPT_R" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_R")
    [ "$MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
    
    CONTENT=$(cat "$SCRIPT_R")
    if echo "$CONTENT" | grep -q "library.*drc"; then SCRIPT_HAS_DRC=true; fi
    if echo "$CONTENT" | grep -q "drm("; then SCRIPT_HAS_DRC=true; fi
fi

# 6. Check 'drc' Installation
DRC_INSTALLED=false
if R --slave -e "library(drc)" >/dev/null 2>&1; then
    DRC_INSTALLED=true
fi

# Export to JSON
cat > /tmp/task_result.json << EOF
{
    "rye_exists": $RYE_EXISTS,
    "rye_is_new": $RYE_IS_NEW,
    "rye_model_count": $RYE_MODEL_COUNT,
    "rye_has_cols": $([ "$RYE_HAS_COLS" = "True" ] && echo true || echo false),
    "rye_ed50_valid": $([ "$RYE_ED50_VALID" = "True" ] && echo true || echo false),
    "alba_exists": $ALBA_EXISTS,
    "alba_is_new": $ALBA_IS_NEW,
    "alba_has_herbs": $([ "$ALBA_HAS_HERBS" = "True" ] && echo true || echo false),
    "alba_si_valid": $([ "$ALBA_SI_VALID" = "True" ] && echo true || echo false),
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "script_modified": $SCRIPT_MODIFIED,
    "script_has_drc": $SCRIPT_HAS_DRC,
    "drc_installed": $DRC_INSTALLED,
    "task_start_time": $TASK_START,
    "timestamp": $NOW
}
EOF

echo "Result JSON content:"
cat /tmp/task_result.json