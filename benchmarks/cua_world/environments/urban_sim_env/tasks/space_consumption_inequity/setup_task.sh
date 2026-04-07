#!/bin/bash
echo "=== Setting up space_consumption_inequity task ==="

source /workspace/scripts/task_utils.sh

# Create directories with proper permissions
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects

# Timestamp for anti-gaming (verification requires files modified AFTER this time)
date +%s > /home/ga/.task_start_time

# Verify data existence
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found. Task environment is invalid."
    exit 1
fi

# Pre-populate the Jupyter Notebook to guide the agent
cat > /home/ga/urbansim_projects/notebooks/space_consumption.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Space Consumption Inequity Analysis\n",
    "\n",
    "Analyze how residential square footage per capita varies across income groups.\n",
    "\n",
    "## Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Join them together (households -> buildings -> parcels -> zones).\n",
    "- Filter out households with 0 or missing `persons`.\n",
    "- Compute `unit_sqft`: use `sqft_per_unit` if available, otherwise `building_sqft / residential_units`.\n",
    "- Filter out records where `unit_sqft` is missing, < 100, or > 20000.\n",
    "- Compute `sqft_per_person` = `unit_sqft / persons`.\n",
    "- Create 10 income deciles (e.g., using `pd.qcut` on income).\n",
    "- Save decile stats (median_income, median_unit_sqft, median_sqft_per_person, household_count) to `../output/space_by_income_decile.csv`.\n",
    "- Save zone stats (median_sqft_per_person, household_count) for zones with >= 50 valid households to `../output/space_by_zone.csv`.\n",
    "- Save a bar chart of median_sqft_per_person by decile to `../output/space_inequity_chart.png`.\n",
    "- Calculate the Top-to-Bottom Space Ratio (Decile 10 median_sqft_per_person / Decile 1 median_sqft_per_person) and write it to `../output/space_ratio_report.txt`."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
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
chown ga:ga /home/ga/urbansim_projects/notebooks/space_consumption.ipynb

# Launch Jupyter Lab if not already running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Launch and arrange Firefox
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/space_consumption.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/space_consumption.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss popups and maximize Firefox for the agent
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot of correct setup state
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="