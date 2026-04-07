#!/bin/bash
echo "=== Setting up wind_turbine_power_curve task ==="

source /workspace/scripts/task_utils.sh

# Create required directories
mkdir -p /home/ga/RProjects/datasets
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

DATASET_PATH="/home/ga/RProjects/datasets/turbine_scada.csv"

# Remove stale output files BEFORE recording timestamp
rm -f /home/ga/RProjects/output/empirical_power_curve.csv
rm -f /home/ga/RProjects/output/aep_estimation.txt
rm -f /home/ga/RProjects/output/power_curve_comparison.png
rm -f /home/ga/RProjects/turbine_analysis.R

echo "Attempting to download real SCADA dataset..."
wget -q -O "$DATASET_PATH" "https://raw.githubusercontent.com/sivabalanb/Data-Analysis-with-Pandas-and-Python/master/T1.csv" 2>/dev/null || true

# Check if download succeeded and has enough data
if [ ! -f "$DATASET_PATH" ] || [ $(wc -l < "$DATASET_PATH" 2>/dev/null || echo "0") -lt 10000 ]; then
    echo "Download failed or incomplete. Generating realistic fallback dataset..."
    
    # Python script to generate realistic SCADA data with noise, curtailment, and downtime
    cat > /tmp/generate_scada.py << 'EOF'
import csv
import random
import math

with open("/home/ga/RProjects/datasets/turbine_scada.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["Date/Time", "LV ActivePower (kW)", "Wind Speed (m/s)", "Theoretical_Power_Curve (KWh)", "Wind Direction (°)"])
    
    for i in range(50000):
        # Generate wind speed from Weibull
        ws = random.weibullvariate(7.5, 2.0)
        
        # Theoretical power curve (3.6MW turbine)
        if ws < 3.0 or ws > 25.0:
            theo = 0.0
        elif ws > 12.0:
            theo = 3600.0
        else:
            theo = 3600.0 * ((ws - 3.0) / (12.0 - 3.0))**3
            
        # Actual power with real-world anomalies
        rand_val = random.random()
        
        if rand_val < 0.04 and ws > 3.5:
            # Downtime (fault)
            act = 0.0
        elif rand_val < 0.08 and theo > 1000.0:
            # Curtailment (grid limitation)
            act = theo * random.uniform(0.1, 0.7)
        else:
            # Normal operation with noise (higher noise at higher power)
            noise_std = 20.0 + (theo * 0.05)
            act = theo + random.gauss(0, noise_std)
            
        # Ensure active power is sensible
        if act < -50: act = -random.random() * 10
        if act > 3700: act = 3700 + random.gauss(0, 5)
        
        date_str = f"2018-01-01 {i%24:02d}:{(i%60):02d}:00"
        wd = random.uniform(0, 360)
        
        w.writerow([date_str, round(act, 4), round(ws, 4), round(theo, 4), round(wd, 4)])
EOF
    python3 /tmp/generate_scada.py
fi

chown ga:ga "$DATASET_PATH"
DATASET_ROWS=$(wc -l < "$DATASET_PATH")
echo "Dataset ready: $DATASET_ROWS rows"

# Create starter R script BEFORE recording timestamp
cat > /home/ga/RProjects/turbine_analysis.R << 'RSCRIPT'
# Wind Turbine Performance Analysis
# Dataset: /home/ga/RProjects/datasets/turbine_scada.csv

library(dplyr)
library(ggplot2)
# Add your code below to clean data, calculate empirical power curve,
# estimate AEP, and plot the results.

RSCRIPT
chown ga:ga /home/ga/RProjects/turbine_analysis.R

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_ts
echo "Task start timestamp: $(cat /tmp/task_start_ts)"

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/turbine_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/turbine_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="