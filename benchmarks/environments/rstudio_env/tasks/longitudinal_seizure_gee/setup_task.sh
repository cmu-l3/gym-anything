#!/bin/bash
echo "=== Setting up longitudinal_seizure_gee task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Remove stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/RProjects/output/seizure_model_comparison.csv
rm -f /home/ga/RProjects/output/seizure_diagnostics.csv
rm -f /home/ga/RProjects/output/seizure_analysis.png
rm -f /home/ga/RProjects/seizure_analysis.R

# Install required packages if not present
echo "Checking and installing required packages..."
R --vanilla --slave << 'REOF'
pkgs <- c("geepack", "MASS")
for (pkg in pkgs) {
    if (!requireNamespace(pkg, quietly=TRUE)) {
        message(paste("Installing", pkg, "..."))
        install.packages(pkg, repos="https://cloud.r-project.org/", quiet=TRUE)
    } else {
        message(paste(pkg, "already available"))
    }
}
# Verify geepack loads
library(geepack)
message("geepack loaded successfully")
# Verify MASS::epil is accessible
library(MASS)
data(epil)
message(paste("epil dataset loaded:", nrow(epil), "rows"))
REOF

if [ $? -ne 0 ]; then
    echo "WARNING: Package installation encountered issues. Continuing..."
fi

# Create starter R script BEFORE recording timestamp
# (so mtime of starter < task_start; agent must modify it to get credit)
cat > /home/ga/RProjects/seizure_analysis.R << 'RSCRIPT'
# Epilepsy Clinical Trial Analysis — Thall & Vail (1990)
# Biostatistics analysis of longitudinal count data
#
# Dataset: MASS::epil
# Reference: Thall PF, Vail SC (1990). Biometrics 46, 657-671.
#
# TODO: Implement the required analysis pipeline:
# 1. Fit GEE model with exchangeable correlation (geepack)
# 2. Fit GEE with AR-1 correlation structure
# 3. Compare models and write seizure_model_comparison.csv
# 4. Diagnose overdispersion and write seizure_diagnostics.csv
# 5. Create multi-panel figure: seizure_analysis.png

RSCRIPT
chown ga:ga /home/ga/RProjects/seizure_analysis.R

# Record task start timestamp AFTER starter creation (anti-gaming: starter mtime <= task_start)
date +%s > /tmp/longitudinal_seizure_gee_start_ts

# Record initial state
echo '{"model_csv_exists": false, "diag_csv_exists": false, "plot_exists": false}' > /tmp/longitudinal_seizure_gee_initial.json

echo "Task start timestamp: $(cat /tmp/longitudinal_seizure_gee_start_ts)"

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/seizure_analysis.R &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/seizure_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/longitudinal_seizure_gee_start.png

echo "=== Setup Complete ==="
echo "Dataset: MASS::epil (59 patients, 4 periods, epilepsy RCT)"
echo "Task: GEE + GLMM analysis of longitudinal count data"
echo "Outputs expected in: /home/ga/RProjects/output/"
