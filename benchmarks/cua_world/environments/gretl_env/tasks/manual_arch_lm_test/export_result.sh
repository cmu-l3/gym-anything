#!/bin/bash
echo "=== Exporting Manual ARCH-LM Test Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if output files exist
SCRIPT_PATH="/home/ga/Documents/gretl_output/arch_test_script.inp"
RESULTS_PATH="/home/ga/Documents/gretl_output/arch_test_results.txt"

SCRIPT_EXISTS="false"
RESULTS_EXISTS="false"

if [ -f "$SCRIPT_PATH" ]; then SCRIPT_EXISTS="true"; fi
if [ -f "$RESULTS_PATH" ]; then RESULTS_EXISTS="true"; fi

# 3. Calculate Ground Truth using gretlcli
# We run the exact same procedure programmatically to get the correct numbers for this specific dataset version
echo "Calculating ground truth values..."
cat > /tmp/calc_truth.inp << 'EOF'
open usa.gdt --quiet
# 1. Mean equation
ols inf const inf(-1) --quiet
series uhat = $uhat
# 2. Squared residuals
series uhat_sq = uhat^2
# 3. Auxiliary regression
ols uhat_sq const uhat_sq(-1) --quiet
# 4. Calculate stats
scalar sample_size = $T
scalar r_squared = $rsq
scalar lm_stat = sample_size * r_squared
scalar p_val = pvalue(X, 1, lm_stat)

print "GROUND_TRUTH_START"
printf "LM_STAT: %.6f\n", lm_stat
printf "P_VAL: %.6f\n", p_val
printf "R_SQUARED: %.6f\n", r_squared
print "GROUND_TRUTH_END"
EOF

# Run gretlcli and capture output
TRUTH_OUTPUT=$(gretlcli -b /tmp/calc_truth.inp 2>/dev/null)
LM_STAT=$(echo "$TRUTH_OUTPUT" | grep "LM_STAT:" | cut -d' ' -f2)
P_VAL=$(echo "$TRUTH_OUTPUT" | grep "P_VAL:" | cut -d' ' -f2)

echo "Ground Truth - LM: $LM_STAT, P: $P_VAL"

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "results_exists": $RESULTS_EXISTS,
    "ground_truth_lm": "$LM_STAT",
    "ground_truth_pval": "$P_VAL",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 5. Move files for verification
# Copy user outputs to temp for extraction
if [ "$SCRIPT_EXISTS" = "true" ]; then
    cp "$SCRIPT_PATH" /tmp/agent_script.inp
    chmod 644 /tmp/agent_script.inp
fi
if [ "$RESULTS_EXISTS" = "true" ]; then
    cp "$RESULTS_PATH" /tmp/agent_results.txt
    chmod 644 /tmp/agent_results.txt
fi

# Move JSON result
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="