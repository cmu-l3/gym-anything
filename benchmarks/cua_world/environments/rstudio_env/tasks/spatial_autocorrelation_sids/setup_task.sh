#!/bin/bash
echo "=== Setting up spatial_autocorrelation_sids task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Install system dependencies for spatial packages (sf/spdep)
# These are often missing from base R images and required for compilation
echo "Installing system dependencies for spatial packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    libudunits2-dev \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libsqlite3-dev

# Install R packages
echo "Installing sf and spdep..."
R --vanilla --slave << 'REOF'
pkgs <- c("sf", "spdep", "classInt")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE, Ncpus=4)
    } else {
        message(paste(pkg, "already available"))
    }
}
REOF

# Create starter R script
cat > /home/ga/RProjects/sids_analysis.R << 'RSCRIPT'
# Spatial Autocorrelation Analysis of SIDS Rates in NC
#
# Dataset: built-in 'nc.shp' from 'sf' package
# Goal: Detect clusters of SIDS cases (1974)
#
# Steps:
# 1. Load data
# 2. Calculate SIDS Rate (per 1000 births)
# 3. Create spatial weights (Queen)
# 4. Global Moran's I
# 5. Local Moran's I (LISA)
# 6. Visualize clusters

library(sf)
library(spdep)

# Load the North Carolina shapefile
nc <- st_read(system.file("shape/nc.shp", package="sf"), quiet=TRUE)

# Your analysis here...

RSCRIPT
chown ga:ga /home/ga/RProjects/sids_analysis.R

# Record initial state
echo '{"output_files_exist": false}' > /tmp/initial_state.json

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/sids_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/sids_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Dependencies installed. Starter script created."