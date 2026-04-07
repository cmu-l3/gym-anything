#!/bin/bash
echo "=== Setting up ITS Seatbelt Policy Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure output directory exists and is empty
OUTPUT_DIR="/home/ga/RProjects/output"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*
chown -R ga:ga "$OUTPUT_DIR"

# Create a starter script
# We explicitly create it BEFORE the task start timestamp.
# This ensures the agent must modify it (or creating a new one) to get credit.
SCRIPT_PATH="/home/ga/RProjects/its_seatbelt_analysis.R"

cat > "$SCRIPT_PATH" << 'EOF'
# Interrupted Time Series Analysis: UK Seatbelt Law
# Dataset: Seatbelts (built-in)
# Goal: Estimate impact of Feb 1983 law on DriversKilled

# Load libraries
library(stats)
library(utils)

# Load data and convert to data frame
data(Seatbelts)
df <- as.data.frame(Seatbelts)

# TODO:
# 1. Create time variables (time, law, time_after_law)
#    Note: Law start index is 170 (Jan 1983 was last pre-law month)
# 2. Fit segmented regression model with seasonality
# 3. Export model results to output/its_model_results.csv
# 4. Calculate diagnostics (Durbin-Watson) and export to output/its_diagnostics.csv
# 5. Create ITS plot with counterfactual and save to output/its_seatbelt_plot.png

EOF
chown ga:ga "$SCRIPT_PATH"

# Install recommended packages if missing (lmtest for DW test, car)
# We do this quietly so it doesn't distract
echo "Ensuring analysis packages are ready..."
R --slave -e "if(!require('lmtest')) install.packages('lmtest', repos='https://cloud.r-project.org/')" > /dev/null 2>&1
R --slave -e "if(!require('car')) install.packages('car', repos='https://cloud.r-project.org/')" > /dev/null 2>&1

# Record task start timestamp (Anti-gaming: files must be newer than this)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Start RStudio with the starter script
echo "Launching RStudio..."
if ! pgrep -f "rstudio" > /dev/null; then
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio $SCRIPT_PATH &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "rstudio"; then
            echo "RStudio window detected"
            break
        fi
        sleep 1
    done
else
    # If running, just open the file
    su - ga -c "DISPLAY=:1 rstudio $SCRIPT_PATH &" 2>/dev/null || true
fi

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "rstudio" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="