#!/bin/bash
echo "=== Setting up BCI Community Ecology Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/bci_alpha_diversity.csv
rm -f /home/ga/RProjects/output/bci_ordination.csv
rm -f /home/ga/RProjects/output/bci_community_tests.csv
rm -f /home/ga/RProjects/output/bci_community_analysis.png
rm -f /home/ga/RProjects/bci_analysis.R

# Ensure vegan is NOT installed (agent must do it)
# We try to remove it from the system library and user library
echo "Ensuring 'vegan' package is not pre-installed..."
R --vanilla --slave -e "
pkgs <- c('vegan', 'permute', 'lattice')
for (p in pkgs) {
  if (require(p, character.only=TRUE, quietly=TRUE)) {
    remove.packages(p)
    message(paste('Removed', p))
  }
}
" 2>/dev/null || true

# Create a blank starter script
cat > /home/ga/RProjects/bci_analysis.R << 'EOF'
# BCI Community Ecology Analysis
# 
# Goal: Analyze Barro Colorado Island tree census data
# 1. Install & load vegan package
# 2. Calculate diversity indices (Richness, Shannon, Simpson)
# 3. Perform NMDS ordination
# 4. Test environmental drivers (PERMANOVA)
# 5. Create visualization plots

# Load data (requires vegan)
# data(BCI)
# data(BCI.env)

# Your analysis code here...
EOF
chown ga:ga /home/ga/RProjects/bci_analysis.R

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch RStudio
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/bci_analysis.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/bci_analysis.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="