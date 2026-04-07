#!/bin/bash
echo "=== Setting up baseline_parking_demand_estimation task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Verify data has required tables
activate_venv
python -c "
import pandas as pd
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
print(f'Parcels table: {len(parcels)} rows')
print(f'Buildings table: {len(buildings)} rows')
assert len(parcels) > 1000, 'Not enough parcel records'
assert len(buildings) > 1000, 'Not enough building records'
print('Data verification passed')
"

# Create a skeleton notebook for the task
cat > /home/ga/urbansim_projects/notebooks/parking_demand_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Baseline Parking Demand Estimation\n",
    "\n",
    "Estimate off-street parking demand across San Francisco zones.\n",
    "\n",
    "## Task Checklist:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Calculate residential spaces (1.2 per unit) and non-residential spaces (2.5 per 1k sqft)\n",
    "- Aggregate demand by `zone_id`\n",
    "- Aggregate `parcel_acres` directly from the `parcels` table by `zone_id` to avoid double-counting\n",
    "- Merge demand and acres, filter out 0s, calculate `spaces_per_acre`\n",
    "- Sort descending by `total_spaces` and save to `../output/zone_parking_demand.csv`\n",
    "- Create a stacked bar chart of Top 15 zones to `../output/top_parking_zones.png`\n",
    "- Save citywide totals to `../output/citywide_parking_summary.json`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/parking_demand_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/parking_demand_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/parking_demand_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss any potential dialogs and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot after browser is ready
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="