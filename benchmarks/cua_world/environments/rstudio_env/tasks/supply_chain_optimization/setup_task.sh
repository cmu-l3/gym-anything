#!/bin/bash
echo "=== Setting up Supply Chain Optimization Task ==="

source /workspace/scripts/task_utils.sh

# Create directories
mkdir -p /home/ga/RProjects/data
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# 1. Create the locations dataset with realistic coordinates
cat > /home/ga/RProjects/data/locations.csv << 'CSV'
location_id,type,lat,lon,capacity_or_demand
Factory_NY,Factory,40.7128,-74.0060,1000
Factory_TX,Factory,31.9686,-99.9018,1500
Factory_CA,Factory,36.7783,-119.4179,1200
Warehouse_WA,Warehouse,47.7511,-120.7401,500
Warehouse_IL,Warehouse,40.6331,-89.3985,800
Warehouse_GA,Warehouse,32.1656,-82.9001,800
Warehouse_CO,Warehouse,39.5501,-105.7821,600
Warehouse_FL,Warehouse,27.6648,-81.5158,700
CSV
chown ga:ga /home/ga/RProjects/data/locations.csv

# 2. Install required R packages (lpSolve for opt, geosphere for dist, maps for viz)
echo "Installing required R packages..."
R --vanilla --slave << 'REOF'
pkgs <- c("lpSolve", "geosphere", "maps", "ggmap", "sf")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE)
    }
}
REOF

# 3. Create a starter script
cat > /home/ga/RProjects/optimization_analysis.R << 'RCODE'
# Supply Chain Optimization
#
# Goal: Minimize transportation costs from Factories to Warehouses
# Data: /home/ga/RProjects/data/locations.csv
# Rate: $0.02 / km / unit
#
# Libraries likely needed:
# library(tidyverse)
# library(lpSolve)
# library(geosphere)

# Load data
locations <- read.csv("/home/ga/RProjects/data/locations.csv")

# Your analysis here...
RCODE
chown ga:ga /home/ga/RProjects/optimization_analysis.R

# 4. Anti-gaming: Record timestamps
date +%s > /tmp/task_start_time
# Ensure output files don't exist
rm -f /home/ga/RProjects/output/optimal_plan.csv
rm -f /home/ga/RProjects/output/supply_chain_map.png
rm -f /home/ga/RProjects/output/shipping_costs_matrix.csv

# 5. Start RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/optimization_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/optimization_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="