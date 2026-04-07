#!/bin/bash
set -e
echo "=== Setting up AP Topic Modeling Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/RProjects/output
chown ga:ga /home/ga/RProjects/output

# Install system dependencies for topicmodels (GSL)
# The default environment might lack libgsl-dev which is needed for topicmodels compilation
echo "Installing system dependencies..."
apt-get update -qq
apt-get install -y libgsl-dev libgsl0-dev 2>/dev/null || true

# Install required R packages
echo "Installing R packages..."
R --vanilla --slave << 'REOF'
# Function to install if missing
install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(paste("Installing", pkg))
    install.packages(pkg, repos = "https://cloud.r-project.org/", Ncpus = 4)
  }
}

# Core packages for the task
install_if_missing("topicmodels")
install_if_missing("tidytext")
install_if_missing("tm")
install_if_missing("SnowballC")
install_if_missing("reshape2")
install_if_missing("patchwork")
install_if_missing("scales")
install_if_missing("ggplot2")
install_if_missing("dplyr")

# Verify data availability
library(topicmodels)
data("AssociatedPress", package = "topicmodels")
message(paste("AP Data Loaded. Rows:", nrow(AssociatedPress)))
REOF

# Create a blank starter script
cat > /home/ga/RProjects/ap_text_analysis.R << 'EOF'
# AP News Corpus - Topic Modeling Analysis
# Goal: LDA topic modeling and visualization
#
# Libraries: topicmodels, tidytext, tm, ggplot2, dplyr
# Dataset: data("AssociatedPress", package = "topicmodels")

EOF
chown ga:ga /home/ga/RProjects/ap_text_analysis.R

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/ap_text_analysis.R &"
    sleep 10
else
    # Open the script if RStudio is already running
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/ap_text_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize
focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="