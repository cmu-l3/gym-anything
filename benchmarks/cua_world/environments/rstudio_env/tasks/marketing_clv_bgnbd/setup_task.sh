#!/bin/bash
echo "=== Setting up Marketing CLV Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure output directory exists and is clean
mkdir -p /home/ga/RProjects/output
rm -f /home/ga/RProjects/output/customer_predictions.csv
rm -f /home/ga/RProjects/output/frequency_plot.png
rm -f /home/ga/RProjects/output/model_params.txt
rm -f /home/ga/RProjects/clv_analysis.R
chown -R ga:ga /home/ga/RProjects

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time

# Create a starter script
cat > /home/ga/RProjects/clv_analysis.R << 'EOF'
# Customer Lifetime Value Analysis - CDNOW Dataset
# Method: BTYD (BG/NBD Model)

# TODO:
# 1. Install/Load BTYD package
# 2. Load cdnowSummary$cbs
# 3. Estimate parameters (r, alpha, a, b) and save to output/model_params.txt
# 4. Plot calibration (frequency) to output/frequency_plot.png
# 5. Predict expected transactions (52 weeks) and P(Alive)
# 6. Save results to output/customer_predictions.csv

EOF
chown ga:ga /home/ga/RProjects/clv_analysis.R

# Record initial state
echo '{"csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/clv_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/clv_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="