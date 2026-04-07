#!/bin/bash
echo "=== Setting up Wine PCA Clustering Task ==="

source /workspace/scripts/task_utils.sh

# Create project structure
mkdir -p /home/ga/RProjects/datasets
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove any stale outputs
rm -f /home/ga/RProjects/output/*.csv
rm -f /home/ga/RProjects/output/*.png
rm -f /home/ga/RProjects/wine_analysis.R

# Download UCI Wine Quality Datasets (Real Data)
# Using generic URLs to ensure availability, fallback to known mirrors if needed
echo "Downloading datasets..."
WINE_RED_URL="https://archive.ics.uci.edu/ml/machine-learning-databases/wine-quality/winequality-red.csv"
WINE_WHITE_URL="https://archive.ics.uci.edu/ml/machine-learning-databases/wine-quality/winequality-white.csv"

# Download Red Wine
if ! wget -q -O /home/ga/RProjects/datasets/winequality-red.csv "$WINE_RED_URL"; then
    echo "Failed to download red wine data. Using backup source..."
    # Backup source (e.g., from a stable repo or mirror) - simplified for this script
    echo "ERROR: Could not download winequality-red.csv"
    exit 1
fi

# Download White Wine
if ! wget -q -O /home/ga/RProjects/datasets/winequality-white.csv "$WINE_WHITE_URL"; then
    echo "ERROR: Could not download winequality-white.csv"
    exit 1
fi

# Set permissions
chown ga:ga /home/ga/RProjects/datasets/*.csv

# Create a starter script file to guide the agent (optional but helpful)
cat > /home/ga/RProjects/wine_analysis.R << 'EOF'
# Wine Quality Analysis Pipeline
# PCA and K-Means Clustering
#
# Datasets:
# - datasets/winequality-red.csv
# - datasets/winequality-white.csv
# NOTE: Files are semicolon-delimited

library(tidyverse)
library(cluster)
library(gridExtra)

# 1. Data Preparation
# ...

EOF
chown ga:ga /home/ga/RProjects/wine_analysis.R

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time

# Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/wine_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/wine_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/wine_initial.png

echo "=== Setup Complete ==="