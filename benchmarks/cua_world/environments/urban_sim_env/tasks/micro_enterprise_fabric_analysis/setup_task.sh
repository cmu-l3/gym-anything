#!/bin/bash
echo "=== Setting up micro_enterprise_fabric_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Verify data tables
activate_venv
python -c "
import pandas as pd
jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Jobs: {len(jobs)} rows')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(parcels)} rows')
assert len(jobs) > 1000, 'Not enough job records'
print('Data verification passed')
"

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/micro_enterprise_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Micro-Enterprise and Commercial Fabric Analysis\n",
    "\n",
    "Analyze the concentration of small business storefronts across San Francisco.\n",
    "\n",
    "## Requirements:\n",
    "- Load `jobs`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Count jobs per building, keeping only buildings with >= 1 job.\n",
    "- Categorize buildings: Micro/Small (1-10), Medium (11-50), Large (51+).\n",
    "- Join to parcels to get `zone_id`.\n",
    "- Group by `zone_id` and compute the 8 required metrics (counts, percentages, total jobs).\n",
    "- Filter to zones with >= 20 business buildings.\n",
    "- Sort descending by `micro_small_bldg_pct` and grab the Top 15.\n",
    "- Save CSV to `../output/top_micro_enterprise_zones.csv`.\n",
    "- Save stacked horizontal bar chart (building counts by size tier) to `../output/business_size_composition.png`."
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
chown ga:ga /home/ga/urbansim_projects/notebooks/micro_enterprise_analysis.ipynb

# Record initial state
echo '{"notebook_exists": true, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/micro_enterprise_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/micro_enterprise_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="