#!/bin/bash
echo "=== Setting up NOAA Climate Forecast Task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Remove stale output files AND old starter BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/climate_stl_components.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/climate_forecast.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/climate_breakpoints.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/climate_analysis.png 2>/dev/null || true
rm -f /home/ga/RProjects/climate_analysis.R 2>/dev/null || true

echo "Installing required R packages..."
R --vanilla --slave -e "
options(repos = c(CRAN = 'https://cloud.r-project.org'))
pkgs <- c('forecast', 'changepoint', 'ggplot2', 'dplyr', 'tidyr', 'patchwork')
for (pkg in pkgs) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
        cat('Installing', pkg, '\n')
        install.packages(pkg, quiet = TRUE)
    } else {
        cat(pkg, 'already installed\n')
    }
}
cat('Package installation complete\n')
" 2>&1 | tail -10

echo "Creating datasets directory..."
mkdir -p /home/ga/RProjects/datasets
mkdir -p /home/ga/RProjects/output

echo "Downloading NASA GISTEMP v4 global temperature anomaly data..."
# Download the actual GISTEMP dataset from NASA GISS
wget -q --timeout=60 \
    "https://data.giss.nasa.gov/gistemp/tabledata_v4/GLB.Ts+dSST.csv" \
    -O /home/ga/RProjects/datasets/gistemp_global.csv 2>/dev/null

# Verify download was successful
if [ -f /home/ga/RProjects/datasets/gistemp_global.csv ] && \
   [ "$(wc -l < /home/ga/RProjects/datasets/gistemp_global.csv)" -gt "10" ]; then
    echo "GISTEMP dataset downloaded successfully"
    head -5 /home/ga/RProjects/datasets/gistemp_global.csv
    wc -l /home/ga/RProjects/datasets/gistemp_global.csv
else
    echo "ERROR: GISTEMP download failed or file too small"
    echo "Attempting curl fallback..."
    curl -s --max-time 60 \
        "https://data.giss.nasa.gov/gistemp/tabledata_v4/GLB.Ts+dSST.csv" \
        -o /home/ga/RProjects/datasets/gistemp_global.csv 2>/dev/null
    if [ -f /home/ga/RProjects/datasets/gistemp_global.csv ] && \
       [ "$(wc -l < /home/ga/RProjects/datasets/gistemp_global.csv)" -gt "10" ]; then
        echo "GISTEMP dataset downloaded via curl"
    else
        echo "CRITICAL: Dataset download failed — check network connectivity"
        exit 1
    fi
fi

chown -R ga:ga /home/ga/RProjects/

# Create starter R script BEFORE recording timestamp
# (mtime of starter <= task_start; agent must modify it to get credit)
echo "Creating starter R script..."
cat > /home/ga/RProjects/climate_analysis.R << 'RSCRIPT'
# NASA GISTEMP v4 Climate Analysis
# Dataset: Global Mean Surface Temperature Anomaly (1880-2023)
# Source: NASA Goddard Institute for Space Studies
#
# Required outputs:
#   1. /home/ga/RProjects/output/climate_stl_components.csv
#      Columns: year, observed, trend, seasonal, remainder
#      (Annual averages from monthly data, Jan-Dec columns)
#
#   2. /home/ga/RProjects/output/climate_forecast.csv
#      Columns: year, forecast, lower80, upper80, lower95, upper95
#      (10-year ARIMA forecast 2024-2033 on STL trend component)
#
#   3. /home/ga/RProjects/output/climate_breakpoints.csv
#      Columns: breakpoint_year, segment_mean_before, segment_mean_after
#
#   4. /home/ga/RProjects/output/climate_analysis.png
#      3-panel: observed+trend | forecast | changepoints

library(forecast)
library(changepoint)
library(ggplot2)
library(dplyr)
library(tidyr)

# Load the GISTEMP dataset
# Note: First row is a header comment, second row has column names
# Columns: Year, Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec,
#          J-D (annual mean), D-N, DJF, MAM, JJA, SON
gistemp_path <- "/home/ga/RProjects/datasets/gistemp_global.csv"

# Your analysis here...
RSCRIPT

chown ga:ga /home/ga/RProjects/climate_analysis.R

# Record task start timestamp AFTER starter creation (starter mtime <= task_start)
date +%s > /tmp/noaa_climate_forecast_start_ts

echo "Ensuring RStudio is running..."
if ! is_rstudio_running 2>/dev/null; then
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/climate_analysis.R >> /home/ga/rstudio.log 2>&1 &"
    sleep 15
else
    focus_rstudio 2>/dev/null || true
fi

su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/climate_analysis.R >> /home/ga/rstudio.log 2>&1 &" 2>/dev/null || true
sleep 5

take_screenshot /tmp/noaa_climate_forecast_start_screenshot.png

echo "=== NOAA Climate Forecast Setup Complete ==="
echo "Dataset: /home/ga/RProjects/datasets/gistemp_global.csv"
echo "Script:  /home/ga/RProjects/climate_analysis.R"
echo "Output:  /home/ga/RProjects/output/"
