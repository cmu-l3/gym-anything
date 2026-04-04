#!/bin/bash
echo "=== Exporting garch_financial_risk result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/garch_financial_risk_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/garch_financial_risk_end.png

# ---- VaR estimates CSV ----
VAR_CSV="/home/ga/RProjects/output/spy_var_estimates.csv"
VAR_EXISTS=false
VAR_IS_NEW=false
VAR_ROW_COUNT=0
VAR_HAS_CORRECT_COLS=false
VAR_99_MORE_NEGATIVE=false
VOL_IN_RANGE=false

if [ -f "$VAR_CSV" ]; then
    VAR_EXISTS=true
    VAR_MTIME=$(stat -c %Y "$VAR_CSV" 2>/dev/null || echo "0")
    [ "$VAR_MTIME" -gt "$TASK_START" ] && VAR_IS_NEW=true
    VAR_ROW_COUNT=$(awk 'NR>1' "$VAR_CSV" | wc -l)
    HEADER=$(head -1 "$VAR_CSV" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    # Check required columns exist
    HAS_DATE=false; HAS_RETURN=false; HAS_VOL=false; HAS_VAR95=false; HAS_VAR99=false
    echo "$HEADER" | grep -qi "date" && HAS_DATE=true
    echo "$HEADER" | grep -qiE "return|log_return" && HAS_RETURN=true
    echo "$HEADER" | grep -qiE "volatility|vol\b|sigma" && HAS_VOL=true
    echo "$HEADER" | grep -qi "var_95\|var95\|value_at_risk_95" && HAS_VAR95=true
    echo "$HEADER" | grep -qi "var_99\|var99\|value_at_risk_99" && HAS_VAR99=true
    [ "$HAS_DATE" = true ] && [ "$HAS_VOL" = true ] && [ "$HAS_VAR95" = true ] && [ "$HAS_VAR99" = true ] && VAR_HAS_CORRECT_COLS=true

    # Check VaR_99 is more negative than VaR_95 and conditional volatility in range
    python3 << PYEOF
import csv, statistics
try:
    with open("$VAR_CSV") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    def find_col(rows, keywords):
        if not rows: return None
        for k in (rows[0] if rows else {}).keys():
            if any(kw in k.lower() for kw in keywords):
                return k
        return None

    var95_col = find_col(rows, ['var_95', 'var95', 'value_at_risk_95'])
    var99_col = find_col(rows, ['var_99', 'var99', 'value_at_risk_99'])
    vol_col = find_col(rows, ['volatility', 'vol', 'sigma', 'conditional_vol'])

    var95_vals = [float(r[var95_col]) for r in rows if var95_col and r.get(var95_col, '').strip()]
    var99_vals = [float(r[var99_col]) for r in rows if var99_col and r.get(var99_col, '').strip()]
    vol_vals = [float(r[vol_col]) for r in rows if vol_col and r.get(vol_col, '').strip()]

    if var95_vals and var99_vals:
        mean95 = sum(var95_vals)/len(var95_vals)
        mean99 = sum(var99_vals)/len(var99_vals)
        # VaR_99 should be more negative (larger loss) than VaR_95
        if mean99 < mean95:
            print("VAR99_NEGATIVE=true")
        else:
            print("VAR99_NEGATIVE=false")
    else:
        print("VAR99_NEGATIVE=false")

    if vol_vals:
        # Annualized vol: raw sigma * sqrt(252) should be between 0.05 and 1.5
        # If stored as raw sigma: multiply by sqrt(252)
        # If stored already annualized: check directly
        mean_vol = sum(vol_vals)/len(vol_vals)
        # Accept daily sigma or annualized
        annualized = mean_vol * (252**0.5) if mean_vol < 0.1 else mean_vol
        if 0.03 <= annualized <= 2.0:
            print("VOL_IN_RANGE=true")
        else:
            print("VOL_IN_RANGE=false")
    else:
        print("VOL_IN_RANGE=false")

except Exception as e:
    print(f"VAR99_NEGATIVE=false")
    print(f"VOL_IN_RANGE=false")
PYEOF

    # Parse Python flags
    PY_OUT=$(python3 << PYEOF
import csv
try:
    with open("$VAR_CSV") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    def find_col(rows, keywords):
        if not rows: return None
        for k in list(rows[0].keys()):
            if any(kw in k.lower() for kw in keywords):
                return k
        return None
    var95_col = find_col(rows, ['var_95','var95','value_at_risk_95'])
    var99_col = find_col(rows, ['var_99','var99','value_at_risk_99'])
    vol_col = find_col(rows, ['volatility','vol','sigma','conditional_vol'])
    var95_vals = [float(r[var95_col]) for r in rows if var95_col and r.get(var95_col,'').strip()]
    var99_vals = [float(r[var99_col]) for r in rows if var99_col and r.get(var99_col,'').strip()]
    vol_vals = [float(r[vol_col]) for r in rows if vol_col and r.get(vol_col,'').strip()]
    neg_ok = "false"
    if var95_vals and var99_vals:
        m95 = sum(var95_vals)/len(var95_vals)
        m99 = sum(var99_vals)/len(var99_vals)
        neg_ok = "true" if m99 < m95 else "false"
    vol_ok = "false"
    if vol_vals:
        mv = sum(vol_vals)/len(vol_vals)
        ann = mv*(252**0.5) if mv < 0.1 else mv
        vol_ok = "true" if 0.03 <= ann <= 2.0 else "false"
    print(neg_ok + " " + vol_ok)
except:
    print("false false")
PYEOF
)
    VAR_99_MORE_NEGATIVE=$(echo "$PY_OUT" | awk '{print $1}')
    VOL_IN_RANGE=$(echo "$PY_OUT" | awk '{print $2}')
fi

# ---- Backtest CSV ----
BT_CSV="/home/ga/RProjects/output/spy_backtest.csv"
BT_EXISTS=false
BT_IS_NEW=false
BT_HAS_KUPIEC=false

if [ -f "$BT_CSV" ]; then
    BT_EXISTS=true
    BT_MTIME=$(stat -c %Y "$BT_CSV" 2>/dev/null || echo "0")
    [ "$BT_MTIME" -gt "$TASK_START" ] && BT_IS_NEW=true
    grep -qi "kupiec\|pof\|exceedance\|proportion" "$BT_CSV" && BT_HAS_KUPIEC=true
fi

# ---- Plot PNG ----
PLOT_PNG="/home/ga/RProjects/output/spy_garch_report.png"
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
SCRIPT="/home/ga/RProjects/garch_analysis.R"
SCRIPT_IS_NEW=false
SCRIPT_HAS_RUGARCH=false
SCRIPT_HAS_GARCH=false

if [ -f "$SCRIPT" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$SCRIPT_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_NEW=true
    CODE=$(grep -v '^\s*#' "$SCRIPT")
    echo "$CODE" | grep -qiE "ugarchspec|ugarchfit|ugarch|garch" && SCRIPT_HAS_RUGARCH=true
    echo "$CODE" | grep -qiE "ugarchspec\s*\(|ugarchfit\s*\(" && SCRIPT_HAS_GARCH=true
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "var_csv_exists": $VAR_EXISTS,
    "var_csv_is_new": $VAR_IS_NEW,
    "var_csv_row_count": $VAR_ROW_COUNT,
    "var_has_correct_cols": $VAR_HAS_CORRECT_COLS,
    "var99_more_negative_than_var95": $VAR_99_MORE_NEGATIVE,
    "conditional_vol_in_range": $VOL_IN_RANGE,
    "backtest_csv_exists": $BT_EXISTS,
    "backtest_csv_is_new": $BT_IS_NEW,
    "backtest_has_kupiec": $BT_HAS_KUPIEC,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "script_is_new": $SCRIPT_IS_NEW,
    "script_has_rugarch": $SCRIPT_HAS_RUGARCH,
    "script_has_garch_fit": $SCRIPT_HAS_GARCH,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/garch_financial_risk_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/garch_financial_risk_result.json
chmod 666 /tmp/garch_financial_risk_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/garch_financial_risk_result.json"
cat /tmp/garch_financial_risk_result.json
echo "=== Export Complete ==="
