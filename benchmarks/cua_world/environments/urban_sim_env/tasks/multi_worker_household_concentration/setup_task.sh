#!/bin/bash
echo "=== Setting up multi_worker_household_concentration task ==="

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

# Verify data has required tables
activate_venv
python -c "
import pandas as pd
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
pcl = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Households: {len(hh)} rows')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(pcl)} rows')
assert len(hh) > 1000, 'Not enough household records'
assert 'workers' in hh.columns, 'Missing workers column'
assert 'income' in hh.columns, 'Missing income column'
print('Data verification passed')
"

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/worker_demographics_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Multi-Worker Household Concentration Analysis\n",
    "\n",
    "Analyze the spatial concentration of multi-worker households in San Francisco.\n",
    "\n",
    "## Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Categorize households into Zero-Worker (0), Single-Worker (1), and Multi-Worker (>=2)\n",
    "- Compute citywide income averages by category and save to `../output/citywide_worker_income.json`\n",
    "- Join data to assign a `zone_id` to each household\n",
    "- Aggregate metrics by `zone_id` and filter for zones with >= 50 total households\n",
    "- Save the zone-level dataframe to `../output/zone_worker_profiles.csv`\n",
    "- Save a scatter plot (pct_multi_worker vs avg_household_income) to `../output/worker_income_scatter.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/worker_demographics_analysis.ipynb

# Record initial state
echo '{"notebook_exists": true, "json_exists": false, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/worker_demographics_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/worker_demographics_analysis.ipynb"
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