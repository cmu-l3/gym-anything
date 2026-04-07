#!/bin/bash
echo "=== Setting up r_package_dev_statkit task ==="

source /workspace/scripts/task_utils.sh

# Ensure clean state: remove any pre-existing statkit directory or files
rm -rf /home/ga/RProjects/statkit
rm -f /home/ga/RProjects/statkit_*.tar.gz
rm -f /home/ga/RProjects/verify_package.R

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Install required system dependencies quietly to prevent Devtools install from timing out
# Using apt-get to install r-cran binaries is much faster than compiling from source
echo "Ensuring dev tools are installed..."
apt-get update -qq > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libcurl4-openssl-dev libssl-dev libxml2-dev \
    r-cran-devtools r-cran-roxygen2 r-cran-usethis > /dev/null 2>&1 || true

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/ &"
    sleep 8
else
    # Focus existing RStudio
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/ &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="