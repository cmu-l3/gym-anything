#!/bin/bash
echo "=== Setting up Spatial Kriging Soil Task ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Remove stale output files AND old starter BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/zinc_variogram.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/zinc_variogram_points.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/zinc_kriging_predictions.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/zinc_moran_test.csv 2>/dev/null || true
rm -f /home/ga/RProjects/output/zinc_kriging_map.png 2>/dev/null || true
rm -f /home/ga/RProjects/spatial_analysis.R 2>/dev/null || true

echo "Creating output directory..."
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Create starter R script BEFORE recording timestamp
# (mtime of starter <= task_start; agent must modify it to get "script modified" credit)
cat > /home/ga/RProjects/spatial_analysis.R << 'RSCRIPT'
# Geostatistical Analysis: Meuse River Soil Zinc Contamination
# Dataset: meuse + meuse.grid from sp package (155 samples along Meuse river, NL)
#
# Required outputs:
#   1a. /home/ga/RProjects/output/zinc_variogram.csv
#       Columns: model, nugget, sill, range_m
#       (Fitted theoretical variogram model parameters)
#
#   1b. /home/ga/RProjects/output/zinc_variogram_points.csv
#       Columns: dist, gamma, np
#       (Empirical variogram cloud points)
#
#   2.  /home/ga/RProjects/output/zinc_kriging_predictions.csv
#       Columns: x, y, zinc_pred (back-transformed: exp(pred)), zinc_var
#       (Ordinary kriging on 40m grid, back-transform from log scale)
#
#   3.  /home/ga/RProjects/output/zinc_moran_test.csv
#       Columns: statistic, expected, variance, p_value, significant
#       (Moran's I test on OK residuals or raw log-zinc)
#
#   4.  /home/ga/RProjects/output/zinc_kriging_map.png
#       2-panel: bubble map (observed) | kriging prediction map

library(gstat)
library(sp)

# Load the Meuse data
data(meuse)
data(meuse.grid)

# Set spatial coordinates
coordinates(meuse) <- ~x+y
coordinates(meuse.grid) <- ~x+y
gridded(meuse.grid) <- TRUE

# Your analysis here...
RSCRIPT
chown ga:ga /home/ga/RProjects/spatial_analysis.R

# Record task start timestamp AFTER starter creation (starter mtime <= task_start)
date +%s > /tmp/spatial_kriging_soil_start_ts

echo "Installing required R packages..."
R --vanilla --slave -e "
options(repos = c(CRAN = 'https://cloud.r-project.org'))
pkgs <- c('gstat', 'sp', 'sf', 'ape', 'spdep', 'ggplot2', 'dplyr', 'viridis', 'RColorBrewer')
for (pkg in pkgs) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
        cat('Installing', pkg, '\n')
        install.packages(pkg, quiet = TRUE)
    } else {
        cat(pkg, 'already installed\n')
    }
}
cat('Package installation complete\n')
" 2>&1 | tail -12

echo "Verifying Meuse dataset accessibility..."
R --vanilla --slave -e "
library(sp)
data(meuse)
cat('Meuse samples:', nrow(meuse), '\n')
cat('Columns:', paste(names(meuse), collapse=', '), '\n')
cat('Zinc range:', min(meuse\$zinc), '-', max(meuse\$zinc), 'ppm\n')
data(meuse.grid)
cat('Meuse grid points:', nrow(meuse.grid), '\n')
" 2>&1

echo "Ensuring RStudio is running..."
if ! is_rstudio_running 2>/dev/null; then
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/spatial_analysis.R >> /home/ga/rstudio.log 2>&1 &"
    sleep 15
else
    focus_rstudio 2>/dev/null || true
fi

su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/spatial_analysis.R >> /home/ga/rstudio.log 2>&1 &" 2>/dev/null || true
sleep 5

take_screenshot /tmp/spatial_kriging_soil_start_screenshot.png

echo "=== Spatial Kriging Soil Setup Complete ==="
echo "Dataset: sp::meuse (155 samples, Meuse river flood plain)"
echo "Script: /home/ga/RProjects/spatial_analysis.R"
echo "Output: /home/ga/RProjects/output/"
