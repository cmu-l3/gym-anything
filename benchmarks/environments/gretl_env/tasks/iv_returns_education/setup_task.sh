#!/bin/bash
echo "=== Setting up iv_returns_education task ==="

source /workspace/scripts/task_utils.sh

# Standard task setup: kill gretl, restore mroz.gdt, launch
setup_gretl_task "mroz.gdt" "iv_returns_education"

# Record task start timestamp for verifier
date +%s > /tmp/iv_returns_education_start
date --iso-8601=seconds >> /tmp/iv_returns_education_start

# Record baseline: check if output file already exists (it should NOT)
OUTPUT_FILE="/home/ga/Documents/gretl_output/iv_wage_results.txt"
if [ -f "$OUTPUT_FILE" ]; then
    BASELINE_EXISTS="true"
    BASELINE_SIZE=$(wc -c < "$OUTPUT_FILE")
    echo "WARNING: Output file already exists (size: $BASELINE_SIZE bytes)" >&2
else
    BASELINE_EXISTS="false"
    BASELINE_SIZE="0"
fi

echo "$BASELINE_EXISTS $BASELINE_SIZE" > /tmp/iv_baseline_state

echo ""
echo "============================================================"
echo "TASK: Instrumental Variables - Returns to Education"
echo "============================================================"
echo ""
echo "Gretl is open with mroz.gdt loaded."
echo "Dataset: Mroz (1987), 753 married women, PSID 1975."
echo ""
echo "Variables available:"
echo "  lwage     - log hourly wage (missing for non-employed)"
echo "  educ      - years of education"
echo "  exper     - years of work experience"
echo "  expersq   - experience squared"
echo "  fatheduc  - father's years of education"
echo "  motheduc  - mother's years of education"
echo "  inlf      - 1 if in labor force"
echo ""
echo "Goal: Investigate returns to education via IV/2SLS estimation."
echo "Save results to: /home/ga/Documents/gretl_output/iv_wage_results.txt"
echo "============================================================"
