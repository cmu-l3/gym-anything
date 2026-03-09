#!/bin/bash
echo "=== Setting up Chow Structural Break Test ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty of previous results
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/chow_test_results.txt

# Standard setup: Restore dataset and launch Gretl
# We use food.gdt as the base dataset
setup_gretl_task "food.gdt" "chow_test"

# Create a clear instruction file on the desktop as a helpful hint
cat > /home/ga/Desktop/Task_Instructions.txt << 'EOF'
TASK: Chow Structural Break Test

1. The 'food.gdt' dataset is loaded.
2. Run OLS regression: food_exp on const and income.
3. Run Chow test at observation 20.
4. Save ALL output to: /home/ga/Documents/gretl_output/chow_test_results.txt
EOF

echo "=== Setup complete ==="