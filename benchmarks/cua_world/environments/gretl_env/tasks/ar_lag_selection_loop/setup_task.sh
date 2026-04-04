#!/bin/bash
set -e
echo "=== Setting up AR Lag Selection Loop task ==="

source /workspace/scripts/task_utils.sh

# 1. Standard Gretl Setup
# We use usa.gdt (US macroeconomic data)
setup_gretl_task "usa.gdt" "lag_loop"

# 2. Ensure output directory is clean
rm -f /home/ga/Documents/gretl_output/lag_screening.inp
rm -f /home/ga/Documents/gretl_output/lag_screening_report.txt

# 3. Provide a hint/readme file on the desktop (optional but helpful context)
cat > /home/ga/Desktop/Task_Instructions.txt << 'EOF'
TASK: Automate AR Lag Selection

1. Open the script editor in Gretl.
2. Write a script that loops from lag 1 to 4.
3. For each lag i, run an OLS of 'inf' on 'const' and 'inf(-i)'.
4. Save the lag number and R-squared to:
   /home/ga/Documents/gretl_output/lag_screening_report.txt
5. Save your script to:
   /home/ga/Documents/gretl_output/lag_screening.inp
EOF
chown ga:ga /home/ga/Desktop/Task_Instructions.txt

echo "=== Setup complete ==="