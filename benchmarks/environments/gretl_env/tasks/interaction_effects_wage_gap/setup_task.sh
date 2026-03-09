#!/bin/bash
set -e
echo "=== Setting up Interaction Effects Wage Gap Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty of previous results
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/interaction_results.txt

# Setup Gretl with the specific dataset
# This kills existing instances, restores data, and launches Gretl
setup_gretl_task "cps5_small.gdt" "interaction_task"

# Record initial state
echo "Dataset: cps5_small.gdt" > /tmp/initial_state_info.txt
md5sum /home/ga/Documents/gretl_data/cps5_small.gdt >> /tmp/initial_state_info.txt

# Create instructions file for the agent (optional but helpful context)
cat > /home/ga/Documents/gretl_output/task_instructions.txt << 'EOF'
TASK INSTRUCTIONS:
1. Open cps5_small.gdt
2. Create log of wage (lwage)
3. Create interaction: female * exper (female_exper)
4. Run OLS: lwage ~ const + educ + female + exper + female_exper
5. Save results to: /home/ga/Documents/gretl_output/interaction_results.txt
EOF

echo "=== Setup complete ==="