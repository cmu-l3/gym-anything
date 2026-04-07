#!/bin/bash
echo "=== Setting up Forensic Glass Composition Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up previous run artifacts to ensure fresh generation
rm -f /home/ga/RProjects/output/glass_geometric_means.csv
rm -f /home/ga/RProjects/output/glass_clr_transformed.csv
rm -f /home/ga/RProjects/output/glass_biplot.png
rm -f /home/ga/RProjects/output/glass_ternary_si_na_ca.png

# Create a starter script for the agent
cat > /home/ga/RProjects/glass_analysis.R << 'EOF'
# Forensic Glass Analysis using Compositional Data Analysis (CoDa)
# Dataset: MASS::fgl

library(MASS)
data(fgl)

# TODO:
# 1. Install/Load compositional analysis package (e.g. compositions, robCompositions)
# 2. Compute Geometric Means by glass 'type' -> output/glass_geometric_means.csv
# 3. Perform CLR transformation -> output/glass_clr_transformed.csv
# 4. Generate Compositional Biplot -> output/glass_biplot.png
# 5. Generate Ternary Diagram (Si, Na, Ca) -> output/glass_ternary_si_na_ca.png

EOF
chown ga:ga /home/ga/RProjects/glass_analysis.R

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure RStudio is running and focus it
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/glass_analysis.R &"
    sleep 10
else
    # Just open the file if RStudio is already open
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/glass_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="