#!/bin/bash
echo "=== Setting up Returns to Schooling IV Task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects

# Remove relevant packages if they exist to force installation
# This ensures the agent demonstrates ability to manage packages
echo "Ensuring clean state for packages..."
R --vanilla --slave -e "
pkgs <- c('wooldridge', 'AER')
for (p in pkgs) {
    if (require(p, character.only=TRUE, quietly=TRUE)) {
        remove.packages(p)
    }
}
" 2>/dev/null || true

# Create a starter script skeleton (optional but helpful for context)
cat > /home/ga/RProjects/returns_to_schooling.R << 'EOF'
# Returns to Schooling Analysis
# Replicating Card (1995) using IV
#
# TODO:
# 1. Install and load wooldridge, AER
# 2. Load 'card' dataset
# 3. OLS Model: lwage ~ educ + exper + I(exper^2) + black + smsa + south
# 4. IV Model: Instrument educ with nearc4
# 5. Save comparison to output/wage_analysis_comparison.csv
# 6. Save Hausman test to output/hausman_test_result.txt
# 7. Plot instrument relevance to output/first_stage_instrument.png

EOF
chown ga:ga /home/ga/RProjects/returns_to_schooling.R

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/returns_to_schooling.R &"
    sleep 10
else
    # Just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/returns_to_schooling.R &" 2>/dev/null || true
    sleep 3
fi

focus_rstudio
maximize_rstudio

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="