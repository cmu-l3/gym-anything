#!/bin/bash
echo "=== Setting up audit_benford_fraud task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove any stale output files before recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/benford_plot.png
rm -f /home/ga/RProjects/output/benford_stats.csv
rm -f /home/ga/RProjects/output/suspect_invoices.csv
rm -f /home/ga/RProjects/audit_analysis.R

# Pre-install data.table to speed up the agent's installation of benford.analysis
echo "Pre-installing data.table dependency to save time..."
R --vanilla --slave -e "if(!requireNamespace('data.table', quietly=TRUE)) install.packages('data.table', repos='https://cloud.r-project.org/', quiet=TRUE)"

# Create a starter script for the agent
cat > /home/ga/RProjects/audit_analysis.R << 'RSCRIPT'
# Forensic Accounting: Benford's Law Analysis
# Dataset: corporate.payment (from benford.analysis package)
#
# Task Deliverables:
# 1. /home/ga/RProjects/output/benford_plot.png
# 2. /home/ga/RProjects/output/benford_stats.csv
# 3. /home/ga/RProjects/output/suspect_invoices.csv

# Write your code below:

RSCRIPT
chown ga:ga /home/ga/RProjects/audit_analysis.R

# Record task start timestamp AFTER starter creation
# Ensures mtime of starter <= task_start; agent must modify it to get credit
date +%s > /tmp/task_start_time

# Record initial state
echo '{"plot_exists": false, "stats_exists": false, "suspects_exists": false}' > /tmp/initial_state.json

# Launch RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/audit_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/audit_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="