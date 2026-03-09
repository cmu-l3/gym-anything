#!/bin/bash
echo "=== Setting up Dual Axis Macro Plot task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
rm -f /home/ga/Documents/gretl_output/growth_inflation_plot.png
rm -f /home/ga/Documents/gretl_output/growth_inflation_plot.plt
rm -f /tmp/task_result.json

# 2. Setup Gretl with usa.gdt
# This utility kills existing gretl, restores the dataset, and launches gretl
setup_gretl_task "usa.gdt" "macro_plot"

# 3. Create a reminder file on the desktop (optional helper)
cat > /home/ga/Desktop/task_instructions.txt << EOF
TASK: Dual-Axis Macro Plot

1. Create variable 'g_gdp' = 400 * diff(log(gdp))
2. Plot 'g_gdp' (Left Axis) and 'inf' (Right Axis)
3. Save as PNG: /home/ga/Documents/gretl_output/growth_inflation_plot.png
4. Save as PLT: /home/ga/Documents/gretl_output/growth_inflation_plot.plt
EOF

echo "=== Setup Complete ==="