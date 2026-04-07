#!/bin/bash
echo "=== Setting up new_housing_price_premium_analysis task ==="

source /workspace/scripts/task_utils.sh

# Reset output directory
rm -rf /home/ga/urbansim_projects/output/* 2>/dev/null || true
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF UrbanSim data not found"
    exit 1
fi

activate_venv

# Create notebook template
cat > /home/ga/urbansim_projects/notebooks/new_construction_premium.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# New Construction Price Premium Analysis\n",
    "\n",
    "Calculate the price premium of new residential construction vs existing housing for each zone.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` from `../data/sanfran_public.h5`\n",
    "- Filter: `residential_units > 0`, `residential_sales_price > 0`, valid `year_built`\n",
    "- Calculate `price_per_unit = residential_sales_price / residential_units`\n",
    "- Classify Vintage: New (`year_built >= 2000`) vs Existing (`year_built < 2000`)\n",
    "- Aggregate by `zone_id` and vintage: sum of `residential_units`, median of `price_per_unit`\n",
    "- Restructure to 1 row per zone with columns: `new_units`, `existing_units`, `median_price_new`, `median_price_existing`\n",
    "- Filter for significance: `new_units >= 20` AND `existing_units >= 50`\n",
    "- Compute `price_premium_ratio = median_price_new / median_price_existing`\n",
    "- Save CSV to `../output/zone_premium_analysis.csv`\n",
    "- Save scatter plot to `../output/premium_scatter.png`\n",
    "- Save top 10 bar chart to `../output/top_premium_zones.png`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import numpy as np\n",
    "import matplotlib.pyplot as plt\n",
    "\n",
    "# Write your code here\n"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "UrbanSim (Python 3)",
   "language": "python",
   "name": "urbansim"
  },
  "language_info": {
   "name": "python",
   "version": "3.10.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
NOTEBOOK_EOF
chown ga:ga /home/ga/urbansim_projects/notebooks/new_construction_premium.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/new_construction_premium.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/new_construction_premium.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Maximize and clear popups
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="