#!/bin/bash
echo "=== Setting up functional_growth_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create project and output directories
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any potential previous artifacts before setting timestamp
rm -f /home/ga/RProjects/output/fpca_variance.csv
rm -f /home/ga/RProjects/output/mean_growth_curve.png
rm -f /home/ga/RProjects/output/pc1_variation.png
rm -f /home/ga/RProjects/growth_analysis.R

# Create starter script
cat > /home/ga/RProjects/growth_analysis.R << 'RSCRIPT'
# Functional Data Analysis of Growth Curves
# Dataset: 'growth' from the 'fda' package
#
# TODO:
# 1. Install and load 'fda' package
# 2. Extract female height matrix (hgtf) and ages (age)
# 3. Create a B-spline basis and smooth the data
# 4. Perform Functional PCA (FPCA)
# 5. Save the variance explained by the first 4 harmonics to output/fpca_variance.csv
# 6. Save a plot of the mean growth curve to output/mean_growth_curve.png
# 7. Save a plot of the first principal component to output/pc1_variation.png

RSCRIPT
chown ga:ga /home/ga/RProjects/growth_analysis.R

# Record the exact start time for anti-gaming verification
date +%s > /tmp/task_start_ts

# Launch RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/growth_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/growth_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="