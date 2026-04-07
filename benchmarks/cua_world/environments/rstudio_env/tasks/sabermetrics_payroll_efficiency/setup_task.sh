#!/bin/bash
echo "=== Setting up Sabermetrics Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Create Output Directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# 2. Ensure Lahman is NOT installed (Force agent to install it)
echo "Ensuring clean state (removing Lahman if present)..."
R --vanilla --slave -e "if(requireNamespace('Lahman', quietly=TRUE)) remove.packages('Lahman')" 2>/dev/null

# 3. Create starter script
cat > /home/ga/RProjects/sabermetrics_analysis.R << 'EOF'
# Sabermetrics Analysis: Payroll Efficiency & Pythagorean Expectation
# -----------------------------------------------------------------
# Task:
# 1. Install/Load 'Lahman' package
# 2. Join Teams and Salaries (2000-2015)
# 3. Calculate Pythagorean Expectation, Luck, and Cost Per Win
# 4. Save outputs to /home/ga/RProjects/output/

# Your code here...
EOF
chown ga:ga /home/ga/RProjects/sabermetrics_analysis.R

# 4. Remove any previous outputs (Anti-gaming)
rm -f /home/ga/RProjects/output/*.csv
rm -f /home/ga/RProjects/output/*.png

# 5. Record start timestamp
date +%s > /tmp/task_start_time

# 6. Launch RStudio
echo "Starting RStudio..."
if ! is_rstudio_running; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/sabermetrics_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/sabermetrics_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# 7. Focus and Maximize
focus_rstudio
maximize_rstudio
sleep 2

# 8. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="