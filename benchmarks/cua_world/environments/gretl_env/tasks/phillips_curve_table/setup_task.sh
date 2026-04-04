#!/bin/bash
set -e
echo "=== Setting up Phillips Curve Table Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up any previous runs
rm -f /home/ga/Documents/gretl_output/phillips_table.tex
rm -f /tmp/ground_truth.json
mkdir -p /home/ga/Documents/gretl_output

# 2. Setup the task environment using standard util
# This kills existing gretl, restores usa.gdt, and launches it
setup_gretl_task "usa.gdt" "phillips_task"

# 3. Add task-specific instructions to a visible text file (optional but helpful context)
cat > /home/ga/Documents/task_instructions.txt << 'EOF'
TASK: Phillips Curve Model Comparison
=====================================

1. Create variable: gdp_growth = 100 * diff(log(gdp))
2. Estimate 3 models for 'inf':
   - Model 1: const, inf(-1)
   - Model 2: const, inf(-1), gdp_growth
   - Model 3: const, inf(-1), gdp_growth, gdp_growth(-1)
3. Create a Model Table containing all three.
4. Export table as LaTeX to: /home/ga/Documents/gretl_output/phillips_table.tex
EOF

# Ensure instructions are visible/accessible
chown ga:ga /home/ga/Documents/task_instructions.txt

echo "=== Setup complete ==="