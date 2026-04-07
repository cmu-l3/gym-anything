#!/bin/bash
echo "=== Exporting ITS Seatbelt Result ==="

# Source task utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"
SCRIPT_PATH="/home/ga/RProjects/its_seatbelt_analysis.R"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Helper to check file freshness ---
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

# --- Analyze Model Results CSV ---
MODEL_CSV="$OUTPUT_DIR/its_model_results.csv"
MODEL_STATUS=$(check_file "$MODEL_CSV")
MODEL_HAS_LAW="false"
MODEL_HAS_SEASONALITY="false"
MODEL_P_VALUE_EXISTS="false"

if [ "$MODEL_STATUS" = "new" ]; then
    # Use python to parse CSV robustly
    MODEL_ANALYSIS=$(python3 -c "
import csv, sys
try:
    has_law = False
    has_seas = False
    has_p = False
    with open('$MODEL_CSV', 'r') as f:
        reader = csv.DictReader(f)
        headers = [h.lower() for h in reader.fieldnames]
        if any('p_value' in h or 'pr(>|t|)' in h or 'p.value' in h for h in headers):
            has_p = True
        
        for row in reader:
            term = str(row.get('term', '')).lower()
            if not term: # Try first column if term not found
                term = str(list(row.values())[0]).lower()
            
            # Check for intervention term
            if any(x in term for x in ['law', 'interv', 'level']):
                has_law = True
            
            # Check for seasonality (months or harmonic)
            if any(x in term for x in ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'sin', 'cos', 'season']):
                has_seas = True
                
    print(f'{str(has_law).lower()}|{str(has_seas).lower()}|{str(has_p).lower()}')
except:
    print('false|false|false')
")
    MODEL_HAS_LAW=$(echo "$MODEL_ANALYSIS" | cut -d'|' -f1)
    MODEL_HAS_SEASONALITY=$(echo "$MODEL_ANALYSIS" | cut -d'|' -f2)
    MODEL_P_VALUE_EXISTS=$(echo "$MODEL_ANALYSIS" | cut -d'|' -f3)
fi

# --- Analyze Diagnostics CSV ---
DIAG_CSV="$OUTPUT_DIR/its_diagnostics.csv"
DIAG_STATUS=$(check_file "$DIAG_CSV")
DIAG_HAS_DW="false"
DIAG_N_OBS=0
LEVEL_CHANGE_VAL="0"

if [ "$DIAG_STATUS" = "new" ]; then
    DIAG_ANALYSIS=$(python3 -c "
import csv
try:
    has_dw = False
    n_obs = 0
    lvl = 0.0
    with open('$DIAG_CSV', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            metric = str(row.get('metric', '')).lower()
            try:
                val = float(row.get('value', 0))
            except:
                val = 0.0
                
            if 'durbin' in metric or 'dw' in metric:
                has_dw = True
            if 'observations' in metric or 'n_obs' in metric:
                n_obs = int(val)
            if 'level_change' in metric or 'law' in metric:
                lvl = val
    print(f'{str(has_dw).lower()}|{n_obs}|{lvl}')
except:
    print('false|0|0')
")
    DIAG_HAS_DW=$(echo "$DIAG_ANALYSIS" | cut -d'|' -f1)
    DIAG_N_OBS=$(echo "$DIAG_ANALYSIS" | cut -d'|' -f2)
    LEVEL_CHANGE_VAL=$(echo "$DIAG_ANALYSIS" | cut -d'|' -f3)
fi

# --- Analyze Plot ---
PLOT_PNG="$OUTPUT_DIR/its_seatbelt_plot.png"
PLOT_STATUS=$(check_file "$PLOT_PNG")
PLOT_SIZE_BYTES=0
if [ "$PLOT_STATUS" = "new" ]; then
    PLOT_SIZE_BYTES=$(stat -c %s "$PLOT_PNG")
fi

# --- Analyze Script ---
SCRIPT_STATUS=$(check_file "$SCRIPT_PATH")
SCRIPT_HAS_GLM="false"
SCRIPT_HAS_TS="false"

if [ -f "$SCRIPT_PATH" ]; then
    if grep -qi "glm(\|lm(\|ts(" "$SCRIPT_PATH"; then
        SCRIPT_HAS_GLM="true"
    fi
fi

# --- Create JSON Result ---
# Using temp file to ensure atomic write/move
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "model_csv": {
        "status": "$MODEL_STATUS",
        "has_law_term": $MODEL_HAS_LAW,
        "has_seasonality": $MODEL_HAS_SEASONALITY,
        "has_p_value": $MODEL_P_VALUE_EXISTS
    },
    "diagnostics_csv": {
        "status": "$DIAG_STATUS",
        "has_durbin_watson": $DIAG_HAS_DW,
        "n_observations": $DIAG_N_OBS,
        "level_change_estimate": $LEVEL_CHANGE_VAL
    },
    "plot": {
        "status": "$PLOT_STATUS",
        "size_bytes": $PLOT_SIZE_BYTES
    },
    "script": {
        "status": "$SCRIPT_STATUS",
        "has_modeling_code": $SCRIPT_HAS_GLM
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="