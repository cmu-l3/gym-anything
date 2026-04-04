#!/bin/bash
echo "=== Setting up cps_wage_diagnostics task ==="

source /workspace/scripts/task_utils.sh

# Standard task setup: kill gretl, restore cps5_small.gdt, launch
setup_gretl_task "cps5_small.gdt" "cps_wage_diagnostics"

# Record task start timestamp
date +%s > /tmp/cps_wage_diagnostics_start
date --iso-8601=seconds >> /tmp/cps_wage_diagnostics_start

# Record baseline
OUTPUT_FILE="/home/ga/Documents/gretl_output/wage_diagnostics.txt"
if [ -f "$OUTPUT_FILE" ]; then
    BASELINE_EXISTS="true"
    BASELINE_SIZE=$(wc -c < "$OUTPUT_FILE")
    echo "WARNING: Output file already exists (size: $BASELINE_SIZE bytes)" >&2
else
    BASELINE_EXISTS="false"
    BASELINE_SIZE="0"
fi

echo "$BASELINE_EXISTS $BASELINE_SIZE" > /tmp/cps_baseline_state

echo ""
echo "============================================================"
echo "TASK: Log-Wage Regression Diagnostics (CPS Data)"
echo "============================================================"
echo ""
echo "Gretl is open with cps5_small.gdt loaded (1200 workers)."
echo ""
echo "Variables available:"
echo "  wage     - hourly earnings (use log transformation)"
echo "  educ     - years of education"
echo "  exper    - years of potential experience"
echo "  expersq  - experience squared"
echo "  female   - 1 if female"
echo "  black    - 1 if Black"
echo "  metro    - 1 if metropolitan area"
echo "  south, midwest, west - regional dummies"
echo ""
echo "Goal: Estimate log-wage OLS and run full specification diagnostics"
echo "      (RESET test, Breusch-Pagan, White heteroskedasticity tests)."
echo ""
echo "Save results to: /home/ga/Documents/gretl_output/wage_diagnostics.txt"
echo "============================================================"
