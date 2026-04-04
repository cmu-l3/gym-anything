#!/bin/bash
set -e
echo "=== Setting up normality_check_residuals task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl Setup (Kill, Restore Data, Launch)
# This launches Gretl with food.gdt loaded
setup_gretl_task "food.gdt" "normality_check"

# 2. Generate Ground Truth (Hidden from Agent)
# We use gretlcli to run the exact same analysis programmatically
# to establish the correct Chi-square statistic for verification.
echo "Generating ground truth..."
mkdir -p /var/lib/gretl
chmod 777 /var/lib/gretl

cat > /tmp/gen_truth.inp << 'EOF'
open /home/ga/Documents/gretl_data/food.gdt
ols food_exp const income --quiet
series uhat = $uhat
normtest uhat --all --quiet
EOF

# Run gretlcli and capture output
gretlcli -b /tmp/gen_truth.inp > /var/lib/gretl/ground_truth_normality.txt 2>&1

# Extract the Chi-square value for Doornik-Hansen specifically
# Output usually looks like: "Chi-square(2) = 0.536906 [0.7646]"
# We save this specific line for easy parsing
grep "Chi-square" /var/lib/gretl/ground_truth_normality.txt > /var/lib/gretl/truth_stats.txt || true

echo "Ground truth generated at /var/lib/gretl/ground_truth_normality.txt"
chmod 644 /var/lib/gretl/ground_truth_normality.txt /var/lib/gretl/truth_stats.txt

# 3. Clean up any previous run artifacts
rm -f /home/ga/Documents/gretl_output/normality_test.txt
rm -f /home/ga/Documents/gretl_output/residual_hist.png

# 4. Display Instructions
echo ""
echo "============================================================"
echo "TASK: Normality Check of Residuals"
echo "============================================================"
echo ""
echo "The 'food.gdt' dataset is loaded."
echo ""
echo "Steps:"
echo "1. Estimate OLS: food_exp ~ const + income"
echo "2. Save the residuals to the dataset"
echo "3. Run a normality test on the residuals"
echo "4. Save test output to: ~/Documents/gretl_output/normality_test.txt"
echo "5. Plot frequency distribution of residuals (with Normal curve)"
echo "6. Save plot to: ~/Documents/gretl_output/residual_hist.png"
echo "============================================================"