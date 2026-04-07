#!/bin/bash
echo "=== Setting up Macro VAR Canada Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Ensure clean state (remove files if they exist)
rm -f /home/ga/RProjects/output/var_selection.csv
rm -f /home/ga/RProjects/output/var_diagnostics.csv
rm -f /home/ga/RProjects/output/irf_wage_unemployment.png

# Ensure vars package is NOT installed (to test package installation skill)
echo "Ensuring 'vars' package is removed..."
R --vanilla --slave -e "if ('vars' %in% rownames(installed.packages())) remove.packages('vars')" 2>/dev/null

# Create starter script
cat > /home/ga/RProjects/var_analysis.R << 'EOF'
# Macroeconomic VAR Analysis - Canada Dataset
#
# Objectives:
# 1. Install/Load 'vars' package and 'Canada' data
# 2. Select Lag (AIC) -> save to output/var_selection.csv
# 3. Fit VAR model (Order: prod, e, U, rw)
# 4. Diagnostics (Portmanteau, Granger) -> save to output/var_diagnostics.csv
# 5. IRF Plot (rw -> U) -> save to output/irf_wage_unemployment.png

EOF
chown ga:ga /home/ga/RProjects/var_analysis.R

# Record start time
date +%s > /tmp/task_start_time

# Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/var_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/var_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="