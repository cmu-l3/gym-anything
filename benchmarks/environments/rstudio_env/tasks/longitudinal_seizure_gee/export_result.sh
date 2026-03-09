#!/bin/bash
echo "=== Exporting longitudinal_seizure_gee result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/longitudinal_seizure_gee_start_ts 2>/dev/null || echo "0")

take_screenshot /tmp/longitudinal_seizure_gee_end.png

# ---- Model comparison CSV ----
MODEL_CSV="/home/ga/RProjects/output/seizure_model_comparison.csv"
MODEL_EXISTS=false
MODEL_IS_NEW=false
MODEL_ROW_COUNT=0
MODEL_HAS_RR_COL=false
MODEL_HAS_PVAL_COL=false
MODEL_RR_IN_RANGE=false

if [ -f "$MODEL_CSV" ]; then
    MODEL_EXISTS=true
    MODEL_MTIME=$(stat -c %Y "$MODEL_CSV" 2>/dev/null || echo "0")
    [ "$MODEL_MTIME" -gt "$TASK_START" ] && MODEL_IS_NEW=true
    MODEL_ROW_COUNT=$(awk 'NR>1' "$MODEL_CSV" | wc -l)
    # Check for required columns (case-insensitive)
    HEADER=$(head -1 "$MODEL_CSV" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    echo "$HEADER" | grep -qi "treatment_rr\|rate_ratio\|rr\b" && MODEL_HAS_RR_COL=true
    echo "$HEADER" | grep -qi "p_value\|pval\|p\.value\|pvalue" && MODEL_HAS_PVAL_COL=true
    # Check RR values are in biologically plausible range (0.3-2.0)
    python3 << PYEOF
import csv, sys
try:
    with open("$MODEL_CSV") as f:
        reader = csv.DictReader(f)
        for row in reader:
            for col, val in row.items():
                if any(k in col.lower() for k in ['rr', 'rate_ratio', 'treatment_rr']):
                    try:
                        v = float(val)
                        if 0.2 <= v <= 3.0:
                            print("RR_IN_RANGE=true")
                            sys.exit(0)
                    except ValueError:
                        pass
except Exception as e:
    pass
print("RR_IN_RANGE=false")
PYEOF
    # Parse python output for RR range
    RR_CHECK=$(python3 << PYEOF
import csv
try:
    with open("$MODEL_CSV") as f:
        reader = csv.DictReader(f)
        for row in reader:
            for col, val in row.items():
                if any(k in col.lower() for k in ['treatment_rr', 'rr', 'rate_ratio']):
                    try:
                        v = float(val)
                        if 0.2 <= v <= 3.0:
                            print("true")
                            exit(0)
                    except ValueError:
                        pass
except:
    pass
print("false")
PYEOF
)
    [ "$RR_CHECK" = "true" ] && MODEL_RR_IN_RANGE=true
fi

# ---- Diagnostics CSV ----
DIAG_CSV="/home/ga/RProjects/output/seizure_diagnostics.csv"
DIAG_EXISTS=false
DIAG_IS_NEW=false
DIAG_HAS_OVERDISPERSION=false
DIAG_OVERDISPERSION_GT1=false

if [ -f "$DIAG_CSV" ]; then
    DIAG_EXISTS=true
    DIAG_MTIME=$(stat -c %Y "$DIAG_CSV" 2>/dev/null || echo "0")
    [ "$DIAG_MTIME" -gt "$TASK_START" ] && DIAG_IS_NEW=true
    # Check for overdispersion metric
    grep -qi "overdispersion\|dispersion" "$DIAG_CSV" && DIAG_HAS_OVERDISPERSION=true
    # Check overdispersion value > 1 (expected for this dataset)
    OD_CHECK=$(python3 << PYEOF
import csv
try:
    with open("$DIAG_CSV") as f:
        reader = csv.DictReader(f)
        for row in reader:
            metric = str(row.get('metric', '')).lower()
            if 'overdispersion' in metric or 'dispersion' in metric:
                try:
                    v = float(row.get('value', 0))
                    if v > 1.0:
                        print("true")
                        exit(0)
                except ValueError:
                    pass
except:
    pass
print("false")
PYEOF
)
    [ "$OD_CHECK" = "true" ] && DIAG_OVERDISPERSION_GT1=true
fi

# ---- Plot PNG ----
PLOT_PNG="/home/ga/RProjects/output/seizure_analysis.png"
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_KB=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    PLOT_MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    [ "$PLOT_MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE_KB=$(du -k "$PLOT_PNG" 2>/dev/null | cut -f1)
fi

# ---- R Script ----
SCRIPT="/home/ga/RProjects/seizure_analysis.R"
SCRIPT_EXISTS=false
SCRIPT_IS_NEW=false
SCRIPT_HAS_GEE=false
SCRIPT_HAS_OUTPUT=false

if [ -f "$SCRIPT" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$SCRIPT_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_NEW=true
    CODE=$(grep -v '^\s*#' "$SCRIPT")
    echo "$CODE" | grep -qiE "geeglm|gee\s*\(|geese\s*\(|glmmPQL|glm\.nb" && SCRIPT_HAS_GEE=true
    echo "$CODE" | grep -qiE "write\.csv|write_csv|ggsave|png\s*\(" && SCRIPT_HAS_OUTPUT=true
fi

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "model_csv_exists": $MODEL_EXISTS,
    "model_csv_is_new": $MODEL_IS_NEW,
    "model_csv_row_count": $MODEL_ROW_COUNT,
    "model_has_rr_column": $MODEL_HAS_RR_COL,
    "model_has_pval_column": $MODEL_HAS_PVAL_COL,
    "model_rr_in_range": $MODEL_RR_IN_RANGE,
    "diag_csv_exists": $DIAG_EXISTS,
    "diag_csv_is_new": $DIAG_IS_NEW,
    "diag_has_overdispersion": $DIAG_HAS_OVERDISPERSION,
    "diag_overdispersion_gt1": $DIAG_OVERDISPERSION_GT1,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "script_exists": $SCRIPT_EXISTS,
    "script_is_new": $SCRIPT_IS_NEW,
    "script_has_gee_call": $SCRIPT_HAS_GEE,
    "script_has_output_call": $SCRIPT_HAS_OUTPUT,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/longitudinal_seizure_gee_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/longitudinal_seizure_gee_result.json
chmod 666 /tmp/longitudinal_seizure_gee_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/longitudinal_seizure_gee_result.json"
cat /tmp/longitudinal_seizure_gee_result.json
echo "=== Export Complete ==="
