#!/bin/bash
echo "=== Setting up var_granger_macro task ==="

source /workspace/scripts/task_utils.sh

# Standard task setup: kill gretl, restore usa.gdt, launch
setup_gretl_task "usa.gdt" "var_granger_macro"

# Record task start timestamp for verifier
date +%s > /tmp/var_granger_macro_start
date --iso-8601=seconds >> /tmp/var_granger_macro_start

# Record baseline: check if output file already exists
OUTPUT_FILE="/home/ga/Documents/gretl_output/var_macro_results.txt"
if [ -f "$OUTPUT_FILE" ]; then
    BASELINE_EXISTS="true"
    BASELINE_SIZE=$(wc -c < "$OUTPUT_FILE")
    echo "WARNING: Output file already exists (size: $BASELINE_SIZE bytes)" >&2
else
    BASELINE_EXISTS="false"
    BASELINE_SIZE="0"
fi

echo "$BASELINE_EXISTS $BASELINE_SIZE" > /tmp/var_baseline_state

echo ""
echo "============================================================"
echo "TASK: VAR Model & Granger Causality — Macroeconomic Dynamics"
echo "============================================================"
echo ""
echo "Gretl is open with usa.gdt loaded (103 quarterly observations)."
echo ""
echo "Variables available:"
echo "  inf  - quarterly inflation rate"
echo "  i    - nominal interest rate"
echo "  lc   - log real personal consumption"
echo "  ly   - log real disposable income"
echo ""
echo "Goal: Analyze dynamic relationships between inflation (inf)"
echo "      and interest rate (i) using VAR, Granger causality tests,"
echo "      and impulse response functions."
echo ""
echo "Save results to: /home/ga/Documents/gretl_output/var_macro_results.txt"
echo "============================================================"
