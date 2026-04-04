#!/bin/bash
set -euo pipefail

echo "=== Setting up subsample_regression_script task ==="

source /workspace/scripts/task_utils.sh

# Define paths
OUTPUT_FILE="/home/ga/Documents/gretl_output/subsample_results.txt"

# 1. Clean up previous results
rm -f "$OUTPUT_FILE"
mkdir -p "$(dirname "$OUTPUT_FILE")"
chown ga:ga "$(dirname "$OUTPUT_FILE")"

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Setup Gretl with food.gdt
# This kills existing instances, restores the dataset, and launches Gretl
setup_gretl_task "food.gdt" "subsample_script"

# 4. Create instructions file for the agent to reference (optional convenience)
cat > /home/ga/Documents/task_instructions.txt << EOF
TASK: Subsample Regression Analysis Script

1. Open Script Editor: File > Script files > New script
2. Write a script to:
   - Split data into Low Income (income < 15) and High Income (income >= 15)
   - Run OLS regression (food_exp on income) for BOTH groups
   - Save the following stats to /home/ga/Documents/gretl_output/subsample_results.txt:
     * Slope coefficient
     * Standard error
     * R-squared
     * Number of observations (N)

Hint: Use 'smpl ... --restrict' and 'outfile' commands.
EOF
chown ga:ga /home/ga/Documents/task_instructions.txt

echo "=== Setup complete ==="