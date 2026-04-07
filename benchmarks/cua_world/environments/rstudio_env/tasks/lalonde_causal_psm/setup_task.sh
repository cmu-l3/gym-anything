#!/bin/bash
set -e
echo "=== Setting up LaLonde Causal Inference Task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# 2. Clear any previous run artifacts to ensure clean state
rm -f /home/ga/RProjects/output/lalonde_balance_table.csv
rm -f /home/ga/RProjects/output/lalonde_treatment_effects.csv
rm -f /home/ga/RProjects/output/lalonde_love_plot.png
rm -f /home/ga/RProjects/output/lalonde_analysis.R

# 3. Create a starter R script
# We provide a skeleton to guide the agent but do NOT do the work.
cat > /home/ga/RProjects/lalonde_analysis.R << 'EOF'
# Causal Inference Analysis: LaLonde Job Training Data
# Goal: Estimate ATT of NSW program on re78 earnings
#
# Required Packages: MatchIt, cobalt (you may need to install these)
# Dataset: lalonde (from MatchIt)

# 1. Load Libraries & Data
# install.packages(c("MatchIt", "cobalt"))
# library(MatchIt)
# library(cobalt)
# data("lalonde")

# 2. Naive Analysis (Unadjusted)

# 3. Propensity Score Matching (Nearest Neighbor & Full)

# 4. Assess Balance (Love Plot & Table)

# 5. Estimate Treatment Effects

# 6. Save Outputs
# write.csv(balance_table, "output/lalonde_balance_table.csv")
# write.csv(effects_table, "output/lalonde_treatment_effects.csv")
# ggsave("output/lalonde_love_plot.png")
EOF
chown ga:ga /home/ga/RProjects/lalonde_analysis.R

# 4. Record Task Start Time (Critical for Anti-Gaming)
date +%s > /tmp/task_start_time.txt

# 5. Ensure RStudio is running and focused
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/lalonde_analysis.R &"
    # Wait for RStudio to launch
    for i in {1..30}; do
        if is_rstudio_running; then
            break
        fi
        sleep 1
    done
    sleep 5
else
    # If already running, just open the file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/lalonde_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Maximize window
maximize_rstudio

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="