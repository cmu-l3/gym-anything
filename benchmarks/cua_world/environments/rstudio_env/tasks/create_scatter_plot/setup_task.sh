#!/bin/bash
echo "=== Setting up create_scatter_plot task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/RProjects/output
chown ga:ga /home/ga/RProjects/output

# Record task start time
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Check if penguins dataset exists, download if not
if [ ! -f /home/ga/RProjects/datasets/penguins.csv ]; then
    echo "Downloading Palmer Penguins dataset..."
    mkdir -p /home/ga/RProjects/datasets
    wget -q -O /home/ga/RProjects/datasets/penguins.csv \
        "https://raw.githubusercontent.com/allisonhorst/palmerpenguins/main/inst/extdata/penguins.csv" 2>/dev/null || {
        echo "Warning: Could not download penguins dataset"
    }
    chown -R ga:ga /home/ga/RProjects/datasets
fi

# Verify dataset exists and has data - FAIL if missing
if [ -f /home/ga/RProjects/datasets/penguins.csv ]; then
    ROWS=$(awk 'END {print NR}' /home/ga/RProjects/datasets/penguins.csv)
    if [ "$ROWS" -lt 300 ]; then
        echo "ERROR: Penguins dataset incomplete (only $ROWS rows, expected 344)"
        exit 1
    fi
    echo "Penguins dataset verified: $ROWS rows"
else
    echo "ERROR: Penguins dataset not available at /home/ga/RProjects/datasets/penguins.csv"
    echo "Task cannot proceed without dataset"
    exit 1
fi

# Create minimal R script - agent must write all code
cat > /home/ga/RProjects/analysis.R << 'EOF'
# R Analysis Script
# Write your code below

EOF
chown ga:ga /home/ga/RProjects/analysis.R

# Record initial state
echo '{"output_exists": false, "script_modified": false}' > /tmp/initial_state.json

# Take initial screenshot
take_screenshot /tmp/task_start.png

# Ensure RStudio is running
if ! is_rstudio_running; then
    echo "Starting RStudio..."
    su - ga -c "DISPLAY=:1 R_LIBS_USER=/home/ga/R/library rstudio /home/ga/RProjects/analysis.R &"
    sleep 8
else
    # Open the analysis.R file in RStudio
    su - ga -c "DISPLAY=:1 rstudio /home/ga/RProjects/analysis.R &" 2>/dev/null || true
    sleep 3
fi

# Focus and maximize RStudio
focus_rstudio
maximize_rstudio

echo "=== Task setup complete ==="
echo "Instructions: Create a scatter plot using the penguins dataset"
echo "Dataset: /home/ga/RProjects/datasets/penguins.csv"
echo "Output: /home/ga/RProjects/output/penguin_scatter.png"
