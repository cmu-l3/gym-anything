#!/bin/bash
echo "=== Setting up high_rise_fire_resource_demand task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time (anti-gaming)
date +%s > /home/ga/.task_start_time

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

# Verify data table presence
activate_venv
python -c "
import pandas as pd
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Buildings: {len(buildings)} rows, Parcels: {len(parcels)} rows')
assert len(buildings) > 100, 'Not enough building records'
assert len(parcels) > 100, 'Not enough parcel records'
print('Data verification passed')
"

# Create template notebook
cat > /home/ga/urbansim_projects/notebooks/fire_resource_assessment.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Fire Resource Demand Assessment\n",
    "\n",
    "Identify high-rise and large-scale buildings to compute fire resource demand by zone.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Identify high-demand buildings (units >= 30 OR sqft >= 50000 OR stories >= 5). Handle NaNs as 0.\n",
    "- Aggregate metrics to the `zone_id` level\n",
    "- Calculate `fire_resource_score = (high_demand_buildings * 5) + (total_residential_units_in_high_demand * 0.1)`\n",
    "- Filter out zones with 0 high-demand buildings and sort descending by score\n",
    "- Save outputs to `../output/fire_resource_demand.csv`, `../output/safety_summary.json`, and `../output/top_20_fire_demand_zones.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/fire_resource_assessment.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the correct notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/fire_resource_assessment.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/fire_resource_assessment.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="