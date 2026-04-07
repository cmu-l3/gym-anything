#!/bin/bash
echo "=== Exporting Sabermetrics Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. File Existence & Timestamp Checks
MAIN_CSV="$OUTPUT_DIR/mlb_efficiency_data.csv"
UNLUCKY_CSV="$OUTPUT_DIR/unlucky_teams.csv"
EFFICIENT_CSV="$OUTPUT_DIR/efficient_teams.csv"
PLOT_PNG="$OUTPUT_DIR/payroll_vs_wins.png"
SCRIPT="$OUTPUT_DIR/../sabermetrics_analysis.R"

check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "stale"
        fi
    else
        echo "false"
    fi
}

MAIN_EXISTS=$(check_file "$MAIN_CSV")
UNLUCKY_EXISTS=$(check_file "$UNLUCKY_CSV")
EFFICIENT_EXISTS=$(check_file "$EFFICIENT_CSV")
PLOT_EXISTS=$(check_file "$PLOT_PNG")
SCRIPT_MODIFIED=$(check_file "$SCRIPT")

# 3. Data Validation (Python)
# We use Python to parse the CSV and validate the math/values specifically for OAK 2002
# and general column correctness.

VALIDATION_JSON=$(python3 << PYEOF
import pandas as pd
import json
import os

result = {
    "columns_valid": False,
    "oak_2002_found": False,
    "oak_2002_data": {},
    "pythag_correct": False,
    "cpw_correct": False,
    "row_count": 0,
    "years_correct": False
}

csv_path = "$MAIN_CSV"
if os.path.exists(csv_path) and "$MAIN_EXISTS" == "true":
    try:
        df = pd.read_csv(csv_path)
        
        # Normalize columns to lowercase for easier checking
        df.columns = [c.lower() for c in df.columns]
        
        # Check basic stats
        result["row_count"] = len(df)
        
        # Check year range
        if 'yearid' in df.columns:
            years = df['yearid'].unique()
            if min(years) >= 2000 and max(years) <= 2015:
                result["years_correct"] = True
                
        # Check required columns presence
        required = ['teamid', 'yearid', 'r', 'ra']
        # We also need derived columns, checking broadly for names
        derived_candidates = {
            'win_pct': ['expectedwinpct', 'pythag', 'exp_win', 'expwin'],
            'luck': ['luck', 'residual'],
            'cpw': ['costperwin', 'cpw', 'payroll_per_win']
        }
        
        cols_present = all(col in df.columns for col in required)
        result["columns_valid"] = cols_present
        
        # Identify OAK 2002
        oak = df[(df['teamid'] == 'OAK') & (df['yearid'] == 2002)]
        if not oak.empty:
            row = oak.iloc[0]
            result["oak_2002_found"] = True
            
            # Extract raw values
            r = float(row['r'])
            ra = float(row['ra'])
            wins = float(row['w']) if 'w' in row else 103 # Fallback if they dropped W, but likely kept
            
            # Find payroll column (heuristic)
            payroll_col = next((c for c in df.columns if 'payroll' in c or 'salary' in c), None)
            payroll = float(row[payroll_col]) if payroll_col else 0
            
            # Find calculated columns (heuristic)
            # Pythagorean Check
            # Formula: R^2 / (R^2 + RA^2)
            expected_pythag = (r**2) / (r**2 + ra**2)
            
            # Look for their calculated column
            pythag_col = next((c for c in df.columns if any(x in c for x in derived_candidates['win_pct'])), None)
            agent_pythag = float(row[pythag_col]) if pythag_col else 0
            
            if abs(agent_pythag - expected_pythag) < 0.01:
                result["pythag_correct"] = True
                
            # Cost Per Win Check
            # Formula: Payroll / Wins
            expected_cpw = payroll / wins if wins > 0 else 0
            cpw_col = next((c for c in df.columns if any(x in c for x in derived_candidates['cpw'])), None)
            agent_cpw = float(row[cpw_col]) if cpw_col else 0
            
            # Allow some tolerance for rounding or unit differences (e.g. millions vs raw)
            # We check ratio
            if agent_cpw > 0 and (0.95 < (agent_cpw / expected_cpw) < 1.05):
                result["cpw_correct"] = True
                
            result["oak_2002_data"] = {
                "wins": wins,
                "payroll": payroll,
                "agent_pythag": agent_pythag,
                "agent_cpw": agent_cpw
            }
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Check Plot Size
PLOT_SIZE=0
if [ -f "$PLOT_PNG" ]; then
    PLOT_SIZE=$(stat -c %s "$PLOT_PNG")
fi

# 5. Check if Lahman was installed
LAHMAN_INSTALLED=$(R --vanilla --slave -e "cat(requireNamespace('Lahman', quietly=TRUE))" 2>/dev/null)

# 6. Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "main_csv": "$MAIN_EXISTS",
    "unlucky_csv": "$UNLUCKY_EXISTS",
    "efficient_csv": "$EFFICIENT_EXISTS",
    "plot_exists": "$PLOT_EXISTS",
    "plot_size": $PLOT_SIZE,
    "script_modified": "$SCRIPT_MODIFIED",
    "lahman_installed": "$LAHMAN_INSTALLED",
    "data_validation": $VALIDATION_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json