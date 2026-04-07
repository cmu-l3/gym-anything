#!/bin/bash
echo "=== Setting up gentrification_displacement_risk task ==="

source /workspace/scripts/task_utils.sh

# Ensure workspace and output directories exist
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify required dataset exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Create a starter Jupyter notebook
cat > /home/ga/urbansim_projects/notebooks/displacement_risk.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Gentrification Displacement Risk Index\n",
    "\n",
    "Identify zones where vulnerable populations face high real estate market pressure.\n",
    "\n",
    "## Task Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` tables from `../data/sanfran_public.h5`\n",
    "- Join data to compute zone-level metrics\n",
    "- Calculate `pct_low_income` (income < 50000) per zone\n",
    "- Calculate valid `median_sales_price` per zone (excluding 0, missing, NaN)\n",
    "- Filter for zones with >= 50 total households and valid prices\n",
    "- Calculate percentile ranks for `low_income_score` and `market_pressure_score`\n",
    "- Sum them for `displacement_risk_score`\n",
    "- Save sorted CSV to `../output/displacement_risk.csv`\n",
    "- Save JSON summary to `../output/risk_summary.json`\n",
    "- Save scatter plot to `../output/displacement_risk_plot.png`"
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
    "import json\n",
    "\n",
    "# Write your analysis code here\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/displacement_risk.ipynb

# Record initial file states
echo '{"notebook_exists": true, "csv_exists": false, "json_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Start Jupyter Lab if not running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox pointing to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/displacement_risk.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/displacement_risk.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Ensure focus and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot for reference
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="