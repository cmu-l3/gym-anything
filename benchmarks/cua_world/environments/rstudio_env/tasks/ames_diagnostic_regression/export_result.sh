#!/bin/bash
echo "=== Exporting Ames Diagnostic Regression Result ==="

TASK_START=$(cat /tmp/ames_diagnostic_regression_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/ames_diagnostic_regression_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/ames_diagnostic_regression_end_screenshot.png 2>/dev/null || true

PREDICTIONS_CSV="/home/ga/RProjects/output/ames_predictions.csv"
DIAGNOSTICS_CSV="/home/ga/RProjects/output/ames_diagnostics.csv"
COEFFICIENTS_CSV="/home/ga/RProjects/output/ames_coefficients.csv"
PLOT_PNG="/home/ga/RProjects/output/ames_diagnostic_plots.png"
SCRIPT="/home/ga/RProjects/ames_analysis.R"
GROUND_TRUTH="/tmp/.ames_ground_truth.csv"

# ── Predictions CSV + Independent RMSLE Computation ────────────────────────────
PRED_EXISTS=false
PRED_IS_NEW=false
PRED_ROW_COUNT=0
COMPUTED_RMSLE=-1
PRED_COUNT=0

if [ -f "$PREDICTIONS_CSV" ]; then
    PRED_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$PREDICTIONS_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && PRED_IS_NEW=true
    PRED_ROW_COUNT=$(wc -l < "$PREDICTIONS_CSV" 2>/dev/null || echo "0")

    # Independently compute RMSLE (anti-gaming: agent cannot fake this)
    RMSLE_RESULT=$(python3 << 'PYEOF' 2>/dev/null
import csv, math, os, sys

preds_path = "/home/ga/RProjects/output/ames_predictions.csv"
truth_path = "/tmp/.ames_ground_truth.csv"

if not os.path.exists(preds_path) or not os.path.exists(truth_path):
    print("-1|0")
    sys.exit(0)

try:
    # Load ground truth
    truth = {}
    with open(truth_path, newline='') as f:
        for row in csv.DictReader(f):
            truth[int(float(row["Id"]))] = float(row["SalePrice"])

    # Load predictions — flexible column name matching
    preds = {}
    with open(preds_path, newline='') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        id_col = next((h for h in headers if h.lower().strip() in ('id',)), None)
        price_col = next((h for h in headers if 'price' in h.lower() or 'pred' in h.lower() or 'saleprice' in h.lower()), None)
        if not id_col:
            id_col = headers[0] if headers else None
        if not price_col:
            price_col = headers[1] if len(headers) > 1 else None

        if id_col and price_col:
            for row in reader:
                try:
                    pid = int(float(row[id_col].strip()))
                    val = float(row[price_col].strip())
                    if val > 0:
                        preds[pid] = val
                except (ValueError, KeyError):
                    continue

    # Match and compute RMSLE
    matched = [(truth[k], preds[k]) for k in truth if k in preds and preds[k] > 0]
    if len(matched) >= 800:
        ssle = sum((math.log(p) - math.log(t))**2 for t, p in matched)
        rmsle = math.sqrt(ssle / len(matched))
        print(f"{rmsle:.6f}|{len(matched)}")
    else:
        print(f"-1|{len(matched)}")
except Exception as e:
    print(f"-1|0")
PYEOF
)
    COMPUTED_RMSLE=$(echo "$RMSLE_RESULT" | cut -d'|' -f1)
    PRED_COUNT=$(echo "$RMSLE_RESULT" | cut -d'|' -f2)
fi

# ── Diagnostics CSV ────────────────────────────────────────────────────────────
DIAG_EXISTS=false
DIAG_IS_NEW=false
DIAG_ROW_COUNT=0
DIAG_CONTENT="[]"

if [ -f "$DIAGNOSTICS_CSV" ]; then
    DIAG_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$DIAGNOSTICS_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && DIAG_IS_NEW=true
    DIAG_ROW_COUNT=$(wc -l < "$DIAGNOSTICS_CSV" 2>/dev/null || echo "0")

    # Extract diagnostics content as JSON array
    DIAG_CONTENT=$(python3 << 'PYEOF' 2>/dev/null
import csv, json, os
path = "/home/ga/RProjects/output/ames_diagnostics.csv"
if not os.path.exists(path):
    print("[]")
else:
    try:
        with open(path, newline='') as f:
            rows = list(csv.DictReader(f))
        # Normalize keys to lowercase
        cleaned = []
        for r in rows:
            cleaned.append({k.lower().strip(): v.strip() for k, v in r.items()})
        print(json.dumps(cleaned))
    except:
        print("[]")
PYEOF
)
fi

# ── Coefficients CSV ───────────────────────────────────────────────────────────
COEF_EXISTS=false
COEF_IS_NEW=false
COEF_ROW_COUNT=0

if [ -f "$COEFFICIENTS_CSV" ]; then
    COEF_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$COEFFICIENTS_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && COEF_IS_NEW=true
    COEF_ROW_COUNT=$(wc -l < "$COEFFICIENTS_CSV" 2>/dev/null || echo "0")
fi

# ── Diagnostic Plot PNG ────────────────────────────────────────────────────────
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE=0
PLOT_IS_PNG=false

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE=$(stat -c %s "$PLOT_PNG" 2>/dev/null || echo "0")
    PNG_HEADER=$(python3 -c "
with open('$PLOT_PNG', 'rb') as f:
    h = f.read(8)
print(str(h == b'\x89PNG\r\n\x1a\n').lower())
" 2>/dev/null || echo "false")
    PLOT_IS_PNG="$PNG_HEADER"
fi

# ── Script checks ──────────────────────────────────────────────────────────────
SCRIPT_MODIFIED=false
SCRIPT_HAS_VIF=false
SCRIPT_HAS_BPTEST=false
SCRIPT_HAS_COOKS=false
SCRIPT_HAS_LM=false

if [ -f "$SCRIPT" ]; then
    FILE_MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
    grep -qiE "vif\(|vif " "$SCRIPT" 2>/dev/null && SCRIPT_HAS_VIF=true
    grep -qiE "bptest|breusch" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_BPTEST=true
    grep -qiE "cooks\.distance|cooks_distance|cooksd" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_COOKS=true
    grep -qiE "\blm\(|lm " "$SCRIPT" 2>/dev/null && SCRIPT_HAS_LM=true
fi

# ── Build result JSON ──────────────────────────────────────────────────────────
cat > /tmp/ames_diagnostic_regression_result.json << EOF
{
    "task_start": $TASK_START,
    "predictions_csv": {
        "exists": $PRED_EXISTS,
        "is_new": $PRED_IS_NEW,
        "row_count": $PRED_ROW_COUNT,
        "matched_count": $PRED_COUNT,
        "computed_rmsle": $COMPUTED_RMSLE
    },
    "diagnostics_csv": {
        "exists": $DIAG_EXISTS,
        "is_new": $DIAG_IS_NEW,
        "row_count": $DIAG_ROW_COUNT,
        "content": $DIAG_CONTENT
    },
    "coefficients_csv": {
        "exists": $COEF_EXISTS,
        "is_new": $COEF_IS_NEW,
        "row_count": $COEF_ROW_COUNT
    },
    "plot_png": {
        "exists": $PLOT_EXISTS,
        "is_new": $PLOT_IS_NEW,
        "size_bytes": $PLOT_SIZE,
        "is_valid_png": $PLOT_IS_PNG
    },
    "script": {
        "modified": $SCRIPT_MODIFIED,
        "has_vif": $SCRIPT_HAS_VIF,
        "has_bptest": $SCRIPT_HAS_BPTEST,
        "has_cooks_distance": $SCRIPT_HAS_COOKS,
        "has_lm": $SCRIPT_HAS_LM
    }
}
EOF

chmod 666 /tmp/ames_diagnostic_regression_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/ames_diagnostic_regression_result.json
