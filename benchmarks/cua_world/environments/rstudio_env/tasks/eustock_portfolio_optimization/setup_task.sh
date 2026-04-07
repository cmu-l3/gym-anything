#!/bin/bash
echo "=== Setting up Portfolio Optimization Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove stale output files to ensure fresh generation
rm -f /home/ga/RProjects/output/min_var_weights.csv
rm -f /home/ga/RProjects/output/returns_summary.csv
rm -f /home/ga/RProjects/output/efficient_frontier.png
rm -f /home/ga/RProjects/portfolio_analysis.R

# Install QuadProg if not present (standard for portfolio optimization)
echo "Checking dependencies..."
R --vanilla --slave << 'REOF'
if (!requireNamespace("quadprog", quietly=TRUE)) {
    install.packages("quadprog", repos="https://cloud.r-project.org/", quiet=TRUE)
}
if (!requireNamespace("tseries", quietly=TRUE)) {
    install.packages("tseries", repos="https://cloud.r-project.org/", quiet=TRUE)
}
REOF

# Create starter R script
# We create this BEFORE recording the start time so the agent must modify it
cat > /home/ga/RProjects/portfolio_analysis.R << 'RSCRIPT'
# Portfolio Optimization - EuStockMarkets
#
# Data: EuStockMarkets (DAX, SMI, CAC, FTSE)
# Goal: Find Global Minimum Variance Portfolio (Long-Only)
#
# Deliverables:
# 1. /home/ga/RProjects/output/min_var_weights.csv
# 2. /home/ga/RProjects/output/returns_summary.csv
# 3. /home/ga/RProjects/output/efficient_frontier.png

library(ggplot2)

# Load data
data(EuStockMarkets)

# Your analysis here...
RSCRIPT
chown ga:ga /home/ga/RProjects/portfolio_analysis.R

# Record task start timestamp (Anti-Gaming)
date +%s > /tmp/task_start_time

# Record initial state
echo '{"weights_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure RStudio is running and focus it
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/portfolio_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/portfolio_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="