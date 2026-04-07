#!/bin/bash
echo "=== Setting up Airport Network Resilience Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/airport_centrality.csv
rm -f /home/ga/RProjects/output/airport_communities.csv
rm -f /home/ga/RProjects/output/airport_resilience.csv
rm -f /home/ga/RProjects/output/airport_network.png
rm -f /home/ga/RProjects/airport_network_analysis.R

# Create a starter R script
cat > /home/ga/RProjects/airport_network_analysis.R << 'EOF'
# US Airport Network Analysis
# ---------------------------
# Goal: Centrality, Community Detection, and Resilience Analysis
# Input: igraphdata::USairports

# TODO: Install and load required packages
# TODO: Load data
# TODO: Perform analysis and save outputs to output/ directory
EOF
chown ga:ga /home/ga/RProjects/airport_network_analysis.R

# Record task start timestamp (anti-gaming)
# We do this AFTER creating the starter file so we can check if the user modified it
date +%s > /tmp/task_start_time

# Record initial state
echo '{"initial_files_exist": false}' > /tmp/initial_state.json

# Uninstall igraph/igraphdata if they happen to be pre-installed (to enforce task requirement)
# This ensures the agent must demonstrate ability to install packages
echo "Ensuring test environment state..."
R --vanilla --slave -e "
pkgs <- c('igraph', 'igraphdata')
for(p in pkgs) {
  if(p %in% rownames(installed.packages())) remove.packages(p)
}
" > /dev/null 2>&1

# Launch RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/airport_network_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/airport_network_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Instructions: Analyze USairports using igraph."
echo "Note: You must install the required packages."