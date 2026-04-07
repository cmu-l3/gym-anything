#!/bin/bash
echo "=== Setting up import_analyze_csv task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# CRITICAL: Clean up any pre-existing notebook
echo "Cleaning pre-existing notebooks..."
rm -rf /home/ga/notebooks/wine_analysis.ipynb 2>/dev/null || true
rm -rf /home/ga/notebooks/.ipynb_checkpoints 2>/dev/null || true

# Ensure the datasets are in place
if [ ! -f /home/ga/datasets/winequality-red.csv ]; then
    echo "Copying wine quality dataset..."
    mkdir -p /home/ga/datasets
    cp /workspace/data/winequality-red.csv /home/ga/datasets/
    chown -R ga:ga /home/ga/datasets
fi

# Verify the dataset is real and has content
LINES=$(wc -l < /home/ga/datasets/winequality-red.csv)
echo "Wine quality dataset has $LINES lines"
if [ "$LINES" -lt 1000 ]; then
    echo "ERROR: Wine quality dataset seems too small ($LINES lines)"
    exit 1
fi

# Ensure notebooks directory exists
mkdir -p /home/ga/notebooks
chown ga:ga /home/ga/notebooks

# Kill any running Jupyter instances to start fresh
pkill -f jupyter 2>/dev/null || true
sleep 2

# Close any Firefox windows
pkill -f firefox 2>/dev/null || true
sleep 2

# Record start time for timestamp validation
echo "$(date +%s)" > /tmp/episode_start_time
echo "Episode start time recorded: $(cat /tmp/episode_start_time)"

# Launch Navigator on Home tab (shows Jupyter Notebook launch button)
navigate_to_tab "home"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "1. Launch Jupyter Notebook from Navigator Home tab"
echo "2. In Jupyter (Firefox), navigate to ~/notebooks/"
echo "3. Create a new Python 3 notebook"
echo "4. Import pandas and matplotlib, load winequality-red.csv"
echo "5. Display .head(), .describe(), create alcohol histogram"
echo "6. Save as wine_analysis.ipynb"
