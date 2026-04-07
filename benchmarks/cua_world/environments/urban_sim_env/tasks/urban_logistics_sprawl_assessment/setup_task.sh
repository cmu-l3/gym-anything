#!/bin/bash
echo "=== Setting up urban_logistics_sprawl_assessment task ==="

source /workspace/scripts/task_utils.sh

# Create output and notebooks directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown ga:ga /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/notebooks

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
print(f'Jobs table: {len(jobs)} rows')
print(f'Buildings table: {len(buildings)} rows')
assert len(jobs) > 100, 'Not enough job records'
print('Data verification passed')
"

# Create skeleton notebook
cat > /home/ga/urbansim_projects/notebooks/logistics_assessment.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Urban Logistics Sprawl Assessment\n",
    "\n",
    "Identify 'logistics candidate' buildings and aggregate them by zone.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings`, `jobs`, `parcels` from `../data/sanfran_public.h5`\n",
    "- Group jobs by building_id to find total jobs per building\n",
    "- Logistics heuristic: `non_residential_sqft >= 40000` AND (`jobs == 0` OR `sqft/jobs >= 1000`)\n",
    "- Join candidate buildings to parcels to get `zone_id`\n",
    "- Aggregate by zone_id: count of candidates and sum of sqft\n",
    "- Export CSV to `../output/logistics_zones.csv`\n",
    "- Export summary JSON to `../output/logistics_summary.json`\n",
    "- Export top 15 zones bar chart to `../output/top_logistics_zones.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/logistics_assessment.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/logistics_assessment.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/logistics_assessment.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot after browser is ready
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="