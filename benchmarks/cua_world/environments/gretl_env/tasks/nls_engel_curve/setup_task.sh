#!/bin/bash
set -e
echo "=== Setting up nls_engel_curve task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/nls_engel.inp
rm -f /home/ga/Documents/gretl_output/nls_engel_output.txt

# Setup Gretl with food.gdt dataset
# This kills existing instances, restores the dataset, and launches Gretl
setup_gretl_task "food.gdt" "nls_task"

# Additional instruction file for the agent (optional but helpful context)
cat > /home/ga/Documents/gretl_output/README.txt << 'EOF'
Task: Nonlinear Least Squares (NLS) Estimation
----------------------------------------------
Model: food_exp = alpha + beta * income^gamma

Steps:
1. Create a script that defines scalars (alpha=50, beta=10, gamma=0.5).
2. Use 'outfile' to save output to 'nls_engel_output.txt'.
3. Run 'nls' estimation for the model.
4. Save your script as 'nls_engel.inp'.
EOF

echo "=== Setup complete ==="