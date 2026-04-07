#!/bin/bash
echo "=== Setting up migration_flow_chord task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/net_migration_summary.csv
rm -f /home/ga/RProjects/output/migration_matrix.csv
rm -f /home/ga/RProjects/output/migration_chord.png
rm -f /home/ga/RProjects/migration_analysis.R

# Install required packages (circlize, migest, and tidyverse helpers)
echo "Checking and installing required packages (this may take a minute)..."
R --vanilla --slave << 'REOF'
pkgs <- c("circlize", "migest", "dplyr", "tidyr")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE)
    } else {
        message(paste(pkg, "already available"))
    }
}
# Verify package loads
if(requireNamespace("migest", quietly=TRUE)) {
    message("migest available")
}
if(requireNamespace("circlize", quietly=TRUE)) {
    message("circlize available")
}
REOF

# Create starter R script BEFORE recording timestamp
# (mtime of starter < task_start; agent must modify it to get credit)
cat > /home/ga/RProjects/migration_analysis.R << 'RSCRIPT'
# Global Migration Flow Visualization (2005-2010)
#
# Dataset: migest::df_m0510
#
# TODO:
# 1. Load data from migest::df_m0510
# 2. Calculate net migration by region and save to /home/ga/RProjects/output/net_migration_summary.csv
# 3. Filter flows > 50,000 and save to /home/ga/RProjects/output/migration_matrix.csv
# 4. Generate a chord diagram using circlize::chordDiagram()
# 5. Save the plot to /home/ga/RProjects/output/migration_chord.png

RSCRIPT
chown ga:ga /home/ga/RProjects/migration_analysis.R

# Record task start timestamp AFTER starter creation
date +%s > /tmp/task_start_ts

echo "Task start timestamp: $(cat /tmp/task_start_ts)"

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/migration_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/migration_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="