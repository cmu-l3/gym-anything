#!/bin/bash
echo "=== Setting up BFI IRT Psychometrics Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean any previous outputs to ensure fresh generation
rm -f /home/ga/RProjects/output/bfi_reliability.csv
rm -f /home/ga/RProjects/output/bfi_grm_parameters.csv
rm -f /home/ga/RProjects/output/bfi_item_fit.csv
rm -f /home/ga/RProjects/output/bfi_irt_plots.png
rm -f /home/ga/RProjects/bfi_irt_analysis.R

# Create a starter script to guide the agent (and define the workspace)
# We set the mtime back so we can detect if the agent modifies it
cat > /home/ga/RProjects/bfi_irt_analysis.R << 'EOF'
# Psychometric Analysis of the Big Five Inventory (BFI)
# Dataset: psych::bfi (25 items, 5 factors)
#
# TODO:
# 1. Install and load packages (psych, mirt)
# 2. Prepare data (handle missing, reverse code: A1, C4, C5, E1, E2, O2, O5)
# 3. Calculate Cronbach's alpha
# 4. Fit Graded Response Model (GRM)
# 5. Export results to /home/ga/RProjects/output/
EOF
chown ga:ga /home/ga/RProjects/bfi_irt_analysis.R
# Set mtime to past to ensure we detect modification
touch -d "2 hours ago" /home/ga/RProjects/bfi_irt_analysis.R

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/bfi_irt_analysis.R &"
    sleep 10
else
    # Open the specific file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/bfi_irt_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Maximize and focus RStudio
wait_for_rstudio 60
maximize_rstudio
focus_rstudio

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="