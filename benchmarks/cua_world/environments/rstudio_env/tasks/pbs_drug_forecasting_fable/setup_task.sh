#!/bin/bash
echo "=== Setting up PBS Drug Forecasting Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/*
rm -f /home/ga/RProjects/forecast_analysis.R

# Create starter script
cat > /home/ga/RProjects/forecast_analysis.R << 'EOF'
# Pharmaceutical Sales Forecasting - Antineoplastic Agents (L01)
# 
# Objective: Forecast total monthly scripts for ATC2 "L01" for the next 3 years.
#
# Steps:
# 1. Install and load 'fpp3' (this includes tsibble, fable, feasts, ggplot2, etc.)
# 2. Load data: data(PBS)
# 3. Filter for ATC2 == "L01"
# 4. Aggregate to get total monthly scripts (Hint: summarise)
# 5. Plot STL decomposition -> save to output/l01_decomposition.png
# 6. Model: Fit ETS() and ARIMA()
# 7. Compare accuracy -> save to output/l01_model_accuracy.csv
# 8. Forecast 3 years (36 months)
# 9. Save forecast values -> output/l01_forecast_values.csv
# 10. Plot forecast -> output/l01_forecast_plot.png

# Write your code here...

EOF
chown ga:ga /home/ga/RProjects/forecast_analysis.R

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure RStudio is running and open the file
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/forecast_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/forecast_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="