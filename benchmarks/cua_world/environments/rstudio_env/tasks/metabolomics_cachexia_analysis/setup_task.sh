#!/bin/bash
echo "=== Setting up metabolomics_cachexia_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/RProjects/output
mkdir -p /home/ga/RProjects/datasets
chown -R ga:ga /home/ga/RProjects

# Remove any stale output files before setting task start time (anti-gaming)
rm -f /home/ga/RProjects/output/metabolomics_results.csv
rm -f /home/ga/RProjects/output/volcano_plot.png
rm -f /home/ga/RProjects/cachexia_analysis.R

# Download the real dataset
echo "Downloading human cachexia dataset from MetaboAnalyst repository..."
DATASET_PATH="/home/ga/RProjects/datasets/human_cachexia.csv"
wget -q -O "$DATASET_PATH" "https://raw.githubusercontent.com/xia-lab/MetaboAnalystR/master/data/human_cachexia.csv" 2>/dev/null

if [ ! -f "$DATASET_PATH" ] || [ $(wc -l < "$DATASET_PATH" 2>/dev/null || echo "0") -lt 50 ]; then
    echo "ERROR: Failed to download dataset. Creating a minimal fallback dataset to allow execution..."
    # Fallback to prevent complete failure if internet is flaky
    cat > "$DATASET_PATH" << EOF
Patient.ID,Muscle.wasting,Metabolite_A,Metabolite_B,Metabolite_C
P1,Cachexic,2.5,NA,5.1
P2,Cachexic,2.8,3.2,4.9
P3,Control,1.1,1.5,5.0
P4,Control,1.2,1.8,5.2
P5,Cachexic,3.0,3.5,4.8
P6,Control,1.0,1.2,5.1
EOF
fi

chown ga:ga "$DATASET_PATH"
DATASET_ROWS=$(wc -l < "$DATASET_PATH" 2>/dev/null)
echo "Dataset verified: $DATASET_ROWS rows downloaded."

# Create starter R script BEFORE recording timestamp
# (mtime of starter <= task_start; agent must modify it to get credit)
cat > /home/ga/RProjects/cachexia_analysis.R << 'RSCRIPT'
# Cachexia Biomarker Discovery Analysis
#
# Dataset: /home/ga/RProjects/datasets/human_cachexia.csv
#
# TODO:
# 1. Load data
# 2. Impute missing values (half of minimum positive value per metabolite)
# 3. Log2 transform metabolite concentrations
# 4. Perform Welch's t-test comparing Cachexic vs Control for each metabolite
# 5. Calculate Log2FC and BH-adjusted FDR
# 6. Save results to /home/ga/RProjects/output/metabolomics_results.csv
# 7. Create Volcano plot and save to /home/ga/RProjects/output/volcano_plot.png

library(tidyverse)

# Begin your analysis below...

RSCRIPT
chown ga:ga /home/ga/RProjects/cachexia_analysis.R

# Record task start timestamp AFTER starter creation
date +%s > /tmp/metabolomics_task_start_ts

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/cachexia_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/cachexia_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/metabolomics_task_start.png

echo "=== Setup Complete ==="