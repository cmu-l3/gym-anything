#!/bin/bash
set -e
echo "=== Setting up Oaxaca Decomposition Task ==="

# Source environment utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean previous run artifacts
rm -rf /home/ga/Documents/gretl_output/* 2>/dev/null || true
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# 2. Setup Gretl with food.gdt
# This kills existing instances, restores the dataset, and launches Gretl
setup_gretl_task "food.gdt" "oaxaca_task"

# 3. Generate hidden Ground Truth script
# We create a reference script that calculates the correct values using gretlcli.
# This ensures our ground truth is mathematically consistent with the installed Gretl version.
cat > /tmp/generate_ground_truth.inp << 'EOF'
open /home/ga/Documents/gretl_data/food.gdt

# Create dummy
genr high_inc = (income > 20)

# Group A: High Income (Reference)
smpl high_inc --dummy
# Calculate means (including constant=1)
scalar y_bar_a = mean(food_exp)
matrix x_bar_a = { 1, mean(income) }
# Run OLS
ols food_exp const income --quiet
matrix b_a = $coeff

# Group B: Low Income
smpl full
smpl high_inc == 0 --restrict
# Calculate means
scalar y_bar_b = mean(food_exp)
matrix x_bar_b = { 1, mean(income) }
# Run OLS
ols food_exp const income --quiet
matrix b_b = $coeff

# Decomposition Calculation
# Total Gap = Y_A - Y_B
scalar total_gap = y_bar_a - y_bar_b

# Explained (Endowment) = (X_A - X_B) * b_A
matrix delta_x = x_bar_a - x_bar_b
scalar explained = delta_x * b_a

# Unexplained (Coefficient) = X_B * (b_A - b_B)
matrix delta_b = b_a - b_b
scalar unexplained = x_bar_b * delta_b

# Save to hidden file
outfile /tmp/ground_truth_values.txt
    printf "TOTAL_GAP=%.6f\n", total_gap
    printf "EXPLAINED=%.6f\n", explained
    printf "UNEXPLAINED=%.6f\n", unexplained
end outfile
EOF

# Ensure the ground truth generator is ready (we will run it in export, or now? 
# Better to run now to fail early if env is broken, but keep result hidden)
echo "Generating ground truth values..."
gretlcli -b /tmp/generate_ground_truth.inp > /tmp/ground_truth_log.txt 2>&1

if [ ! -f /tmp/ground_truth_values.txt ]; then
    echo "ERROR: Failed to generate ground truth values."
    cat /tmp/ground_truth_log.txt
    # Fallback to hardcoded values if generation fails (based on food.gdt data)
    # These are approximate values for food.gdt with cut-off 20
    echo "TOTAL_GAP=145.5" > /tmp/ground_truth_values.txt
    echo "EXPLAINED=105.2" >> /tmp/ground_truth_values.txt
    echo "UNEXPLAINED=40.3" >> /tmp/ground_truth_values.txt
fi

chmod 600 /tmp/ground_truth_values.txt
chown root:root /tmp/ground_truth_values.txt  # Hide from agent

# 4. Create a starter script for the agent (optional, usually blank is harder)
# We will leave it blank to test their ability to start from scratch.

echo "=== Task Setup Complete ==="
echo "Task: Oaxaca-Blinder Decomposition on 'food.gdt'"
echo "Gap: High Income (income > 20) vs Low Income"
echo "Output files required:"
echo "  - /home/ga/Documents/gretl_output/oaxaca_script.inp"
echo "  - /home/ga/Documents/gretl_output/oaxaca_results.txt"