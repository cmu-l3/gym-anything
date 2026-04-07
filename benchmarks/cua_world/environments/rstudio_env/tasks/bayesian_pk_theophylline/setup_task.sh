#!/bin/bash
echo "=== Setting up Bayesian PK Task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directory structure
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# 2. Clean previous run artifacts (anti-gaming)
rm -f /home/ga/RProjects/output/*
rm -f /home/ga/RProjects/pk_bayesian_analysis.R

# 3. Create starter script
# We create this BEFORE the task start timestamp so we can verify if the agent modified it.
cat > /home/ga/RProjects/pk_bayesian_analysis.R << 'EOF'
# Bayesian Population PK Analysis of Theophylline
# Dataset: Theoph (built-in)
#
# Libraries likely needed:
# library(brms) or library(rstanarm)
# library(dplyr)
# library(ggplot2)
# library(bayesplot)
#
# TODO:
# 1. Filter data (Time > 1) and create log_conc
# 2. Fit Model A (Random Intercepts)
# 3. Fit Model B (Random Slopes)
# 4. Check convergence (Rhat, ESS)
# 5. Compare models (LOO)
# 6. Save outputs to /home/ga/RProjects/output/

EOF
chown ga:ga /home/ga/RProjects/pk_bayesian_analysis.R

# 4. Install/Verify necessary Bayesian packages
# brms/rstanarm can be heavy. We try to ensure they are available.
# If installation takes too long, we might need to rely on pre-installed image state.
# Here we do a quick check and install if missing (with timeout protection in hook).
echo "Verifying R packages..."
R --vanilla --slave << 'REOF'
req_pkgs <- c("brms", "rstanarm", "loo", "bayesplot", "ggplot2", "dplyr")
new_pkgs <- req_pkgs[!(req_pkgs %in% installed.packages()[,"Package"])]
if(length(new_pkgs)) { 
  message("Installing missing packages: ", paste(new_pkgs, collapse=", "))
  install.packages(new_pkgs, repos="https://cloud.r-project.org/", Ncpus=4)
}
REOF

# 5. Record task start timestamp (CRITICAL for anti-gaming)
# Files created before this time are considered pre-existing
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 6. Launch RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/pk_bayesian_analysis.R &"
    sleep 10
else
    # Open the specific file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/pk_bayesian_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# 7. Window management
focus_rstudio
maximize_rstudio
sleep 2

# 8. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="