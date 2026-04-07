#!/bin/bash
echo "=== Exporting Actuarial Task Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
MACK_CSV="/home/ga/RProjects/output/mack_estimates.csv"
RISK_CSV="/home/ga/RProjects/output/reserve_risk_metrics.csv"
PLOT_PNG="/home/ga/RProjects/output/development_plot.png"
SCRIPT_R="/home/ga/RProjects/actuarial_reserving.R"

# 1. Analyze Mack Estimates CSV
MACK_EXISTS="false"
MACK_NEW="false"
MACK_TOTAL_IBNR="0"
MACK_VALID_COLS="false"

if [ -f "$MACK_CSV" ]; then
    MACK_EXISTS="true"
    MTIME=$(stat -c %Y "$MACK_CSV")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        MACK_NEW="true"
    fi
    
    # Parse CSV with python to get total IBNR and check columns
    PY_RES=$(python3 << EOF
import pandas as pd
try:
    df = pd.read_csv("$MACK_CSV")
    cols = [c.lower() for c in df.columns]
    req = ['origin_year', 'latest_cumulative', 'ibnr_estimate', 'ultimate_estimate', 'mack_se']
    valid_cols = all(any(r in c for c in cols) for r in req)
    
    # Sum IBNR estimate
    # Find column that looks like IBNR
    ibnr_col = next((c for c in df.columns if 'ibnr' in c.lower()), None)
    if ibnr_col:
        total = df[ibnr_col].sum()
    else:
        total = 0
    
    print(f"{str(valid_cols).lower()}|{total}")
except Exception as e:
    print(f"false|0")
EOF
)
    MACK_VALID_COLS=$(echo "$PY_RES" | cut -d'|' -f1)
    MACK_TOTAL_IBNR=$(echo "$PY_RES" | cut -d'|' -f2)
fi

# 2. Analyze Risk Metrics CSV
RISK_EXISTS="false"
RISK_NEW="false"
RISK_995="0"
RISK_VALID_COLS="false"

if [ -f "$RISK_CSV" ]; then
    RISK_EXISTS="true"
    MTIME=$(stat -c %Y "$RISK_CSV")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        RISK_NEW="true"
    fi

    PY_RES=$(python3 << EOF
import pandas as pd
try:
    df = pd.read_csv("$RISK_CSV")
    # Flexible column checking
    cols = [c.lower() for c in df.columns]
    
    # Check for row with quantile_99.5
    # Assuming structure: metric, value
    # Normalize metric names
    if 'metric' in cols and 'value' in cols:
        val_col = df.columns[cols.index('value')]
        met_col = df.columns[cols.index('metric')]
        
        # Look for 99.5 in the metric column
        row = df[df[met_col].astype(str).str.contains('99.5')]
        if not row.empty:
            val = row.iloc[0][val_col]
        else:
            val = 0
        print(f"true|{val}")
    else:
        # Maybe wide format?
        print("false|0")
except:
    print("false|0")
EOF
)
    RISK_VALID_COLS=$(echo "$PY_RES" | cut -d'|' -f1)
    RISK_995=$(echo "$PY_RES" | cut -d'|' -f2)
fi

# 3. Analyze Plot
PLOT_EXISTS="false"
PLOT_NEW="false"
PLOT_SIZE="0"
if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS="true"
    MTIME=$(stat -c %Y "$PLOT_PNG")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_NEW="true"
    fi
    PLOT_SIZE=$(stat -c %s "$PLOT_PNG")
fi

# 4. Analyze Script
SCRIPT_EXISTS="false"
SCRIPT_NEW="false"
SCRIPT_CONTENT_VALID="false"
if [ -f "$SCRIPT_R" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT_R")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_NEW="true"
    fi
    
    # Check for key function calls
    if grep -q "ChainLadder" "$SCRIPT_R" && grep -q "MackChainLadder" "$SCRIPT_R"; then
        SCRIPT_CONTENT_VALID="true"
    fi
fi

# 5. Check if package is installed (Export Phase check)
PKG_INSTALLED=$(R --slave -e "cat(requireNamespace('ChainLadder', quietly=TRUE))" 2>/dev/null)

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "mack_exists": $MACK_EXISTS,
    "mack_new": $MACK_NEW,
    "mack_total_ibnr": $MACK_TOTAL_IBNR,
    "mack_valid_cols": $MACK_VALID_COLS,
    "risk_exists": $RISK_EXISTS,
    "risk_new": $RISK_NEW,
    "risk_995": $RISK_995,
    "risk_valid_cols": $RISK_VALID_COLS,
    "plot_exists": $PLOT_EXISTS,
    "plot_new": $PLOT_NEW,
    "plot_size": $PLOT_SIZE,
    "script_exists": $SCRIPT_EXISTS,
    "script_new": $SCRIPT_NEW,
    "script_content_valid": $SCRIPT_CONTENT_VALID,
    "pkg_installed": "$PKG_INSTALLED"
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json