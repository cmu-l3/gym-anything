#!/bin/bash
echo "=== Exporting Occupancy Modeling Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# Paths
SELECTION_CSV="/home/ga/RProjects/output/model_selection.csv"
PRED_CSV="/home/ga/RProjects/output/forest_predictions.csv"
PLOT_PNG="/home/ga/RProjects/output/occupancy_plot.png"
SCRIPT="/home/ga/RProjects/occupancy_analysis.R"

# --- Validate Model Selection CSV ---
SELECTION_EXISTS=false
SELECTION_VALID=false
BEST_MODEL=""
MIN_AIC=9999

if [ -f "$SELECTION_CSV" ]; then
    SELECTION_EXISTS=true
    # Parse CSV with python to check AIC values
    PY_RES=$(python3 << 'EOF'
import csv
import sys

csv_file = "/home/ga/RProjects/output/model_selection.csv"
try:
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print("invalid|none|9999")
        sys.exit(0)

    # Normalize column names
    rows_norm = []
    for r in rows:
        new_r = {k.lower().strip(): v for k, v in r.items()}
        rows_norm.append(new_r)
    
    # Check if we have AIC
    has_aic = any('aic' in k for k in rows_norm[0].keys())
    if not has_aic:
        print("invalid|none|9999")
        sys.exit(0)
        
    # Find min AIC and corresponding model name/row
    min_aic = 9999.0
    best_row_idx = -1
    
    for i, r in enumerate(rows_norm):
        # Find AIC value
        aic_key = next((k for k in r.keys() if 'aic' in k and 'delta' not in k), None)
        if aic_key:
            try:
                val = float(r[aic_key])
                if val < min_aic:
                    min_aic = val
                    best_row_idx = i
            except:
                pass
                
    valid = "valid" if len(rows) >= 2 else "invalid"
    print(f"{valid}|{best_row_idx}|{min_aic}")
    
except Exception as e:
    print(f"error|none|9999")
EOF
)
    
    SELECTION_VALID=$(echo "$PY_RES" | cut -d'|' -f1)
    MIN_AIC=$(echo "$PY_RES" | cut -d'|' -f3)
fi

# --- Validate Predictions CSV ---
PRED_EXISTS=false
PRED_VALID=false
NEGATIVE_TREND=false

if [ -f "$PRED_CSV" ]; then
    PRED_EXISTS=true
    PY_RES_PRED=$(python3 << 'EOF'
import csv
import sys
import statistics

csv_file = "/home/ga/RProjects/output/forest_predictions.csv"
try:
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print("invalid|false")
        sys.exit(0)
        
    # Normalize
    rows_norm = []
    for r in rows:
        new_r = {k.lower().strip(): v for k, v in r.items()}
        rows_norm.append(new_r)
        
    # Identify columns
    forest_key = next((k for k in rows_norm[0].keys() if 'forest' in k), None)
    pred_key = next((k for k in rows_norm[0].keys() if 'pred' in k), None)
    
    if not forest_key or not pred_key:
        print("invalid|false")
        sys.exit(0)
        
    forests = []
    preds = []
    
    for r in rows_norm:
        try:
            f_val = float(r[forest_key])
            p_val = float(r[pred_key])
            forests.append(f_val)
            preds.append(p_val)
        except:
            pass
            
    if not forests:
        print("invalid|false")
        sys.exit(0)

    # Check range (probabilities must be 0-1)
    in_range = all(0 <= p <= 1 for p in preds)
    if not in_range:
        print("invalid_range|false")
        sys.exit(0)

    # Check correlation (should be negative for Mallard vs Forest)
    # Simple check: compare start and end if sorted, or correlation
    if len(forests) > 1:
        # Calculate slope or just compare first/last
        # Sort by forest
        zipped = sorted(zip(forests, preds))
        first_p = zipped[0][1]
        last_p = zipped[-1][1]
        neg_trend = last_p < first_p
        
    print(f"valid|{str(neg_trend).lower()}")

except Exception as e:
    print("error|false")
EOF
)
    PRED_VALID_STATUS=$(echo "$PY_RES_PRED" | cut -d'|' -f1)
    [ "$PRED_VALID_STATUS" == "valid" ] && PRED_VALID=true
    NEGATIVE_TREND=$(echo "$PY_RES_PRED" | cut -d'|' -f2)
fi

# --- Validate Plot ---
PLOT_EXISTS=false
PLOT_SIZE_KB=0
if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    PLOT_SIZE_KB=$(du -k "$PLOT_PNG" | cut -f1)
fi

# --- Validate Script ---
SCRIPT_EXISTS=false
SCRIPT_HAS_UNMARKED=false
SCRIPT_HAS_OCCU=false
if [ -f "$SCRIPT" ]; then
    SCRIPT_EXISTS=true
    CONTENT=$(cat "$SCRIPT")
    if echo "$CONTENT" | grep -qi "library.*unmarked"; then SCRIPT_HAS_UNMARKED=true; fi
    if echo "$CONTENT" | grep -qi "occu("; then SCRIPT_HAS_OCCU=true; fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/occupancy_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "selection_csv_exists": $SELECTION_EXISTS,
    "selection_valid": "$SELECTION_VALID",
    "min_aic": $MIN_AIC,
    "predictions_csv_exists": $PRED_EXISTS,
    "predictions_valid": $PRED_VALID,
    "predictions_negative_trend": $NEGATIVE_TREND,
    "plot_exists": $PLOT_EXISTS,
    "plot_size_kb": $PLOT_SIZE_KB,
    "script_exists": $SCRIPT_EXISTS,
    "script_has_unmarked": $SCRIPT_HAS_UNMARKED,
    "script_has_occu": $SCRIPT_HAS_OCCU,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/occupancy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupancy_result.json
chmod 666 /tmp/occupancy_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/occupancy_result.json