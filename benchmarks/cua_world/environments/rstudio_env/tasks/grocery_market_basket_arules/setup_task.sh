#!/bin/bash
echo "=== Setting up Market Basket Analysis Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure output directory exists and has correct permissions
mkdir -p /home/ga/RProjects/output
chown -R ga:ga /home/ga/RProjects/output

# Clean up any previous run artifacts
rm -f /home/ga/RProjects/output/item_frequencies.csv
rm -f /home/ga/RProjects/output/top_association_rules.csv
rm -f /home/ga/RProjects/output/wholemilk_rules.csv
rm -f /home/ga/RProjects/output/rules_network.png
rm -f /home/ga/RProjects/market_basket_analysis.R

# Create a blank starter script
cat > /home/ga/RProjects/market_basket_analysis.R << 'EOF'
# Market Basket Analysis - Groceries Dataset
# Write your code here...

EOF
chown ga:ga /home/ga/RProjects/market_basket_analysis.R

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_time

# Record initial state
echo '{"arules_installed": false}' > /tmp/initial_state.json

# Check if RStudio is running, if not start it
if ! pgrep -f "rstudio" > /dev/null; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/market_basket_analysis.R &"
    sleep 10
else
    # Open the specific file
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/market_basket_analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Setup window
if type focus_rstudio &>/dev/null; then
    focus_rstudio
    maximize_rstudio
else
    # Fallback if utils not loaded
    DISPLAY=:1 wmctrl -a "RStudio" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Instructions: Perform MBA on Groceries dataset."
echo "Note: 'arules' package is NOT installed by default."