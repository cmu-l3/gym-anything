#!/bin/bash
echo "=== Setting up panel_wage_hausman task ==="

source /workspace/scripts/task_utils.sh

# Standard task setup: kill gretl, restore nls_panel.gdt, launch
setup_gretl_task "nls_panel.gdt" "panel_wage_hausman"

# Record task start timestamp
date +%s > /tmp/panel_wage_hausman_start
date --iso-8601=seconds >> /tmp/panel_wage_hausman_start

# Record baseline
OUTPUT_FILE="/home/ga/Documents/gretl_output/panel_results.txt"
if [ -f "$OUTPUT_FILE" ]; then
    BASELINE_EXISTS="true"
    BASELINE_SIZE=$(wc -c < "$OUTPUT_FILE")
    echo "WARNING: Output file already exists (size: $BASELINE_SIZE bytes)" >&2
else
    BASELINE_EXISTS="false"
    BASELINE_SIZE="0"
fi

echo "$BASELINE_EXISTS $BASELINE_SIZE" > /tmp/panel_baseline_state

echo ""
echo "============================================================"
echo "TASK: Panel Data FE vs RE — Hausman Specification Test"
echo "============================================================"
echo ""
echo "Gretl is open with nls_panel.gdt loaded."
echo "Dataset: NLS panel, 716 young women, multiple years."
echo ""
echo "Variables available:"
echo "  lwage   - log hourly wage"
echo "  educ    - years of education"
echo "  exper   - years of work experience"
echo "  expersq - experience squared"
echo "  black   - 1 if Black"
echo "  south   - 1 if southern region"
echo "  union   - 1 if union member"
echo "  tenure  - job tenure in years"
echo ""
echo "Goal: Compare Pooled OLS, FE, and RE estimators."
echo "      Run Hausman test to select appropriate estimator."
echo ""
echo "Save results to: /home/ga/Documents/gretl_output/panel_results.txt"
echo "============================================================"
