#!/bin/bash
echo "=== Setting up family_housing_and_school_demand_assessment task ==="

source /workspace/scripts/task_utils.sh

# Create output directories
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

# Verify data has the correct tables
activate_venv
python -c "
import pandas as pd
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
pcl = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Households table: {len(hh)} rows')
print(f'Buildings table: {len(bld)} rows')
print(f'Parcels table: {len(pcl)} rows')
assert len(hh) > 1000, 'Not enough household records'
assert len(bld) > 1000, 'Not enough building records'
assert len(pcl) > 1000, 'Not enough parcel records'
print('Data verification passed')
"

# Create empty notebook for the task
cat > /home/ga/urbansim_projects/notebooks/family_housing_assessment.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Family Housing and School Demand Assessment\n",
    "\n",
    "Analyze household size distributions across SF to identify \"family-rich\" zones.\n",
    "\n",
    "## Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` data from `../data/sanfran_public.h5`\n",
    "- Join tables to get `zone_id` for each household\n",
    "- Identify Family Households (persons >= 3) and building types (Single-Family vs Multi-Family)\n",
    "- Aggregate by zone, filter out zones with < 50 total households\n",
    "- Find the top 15 zones by family concentration rate\n",
    "- Save outputs:\n",
    "  - Top 15 CSV to `../output/top_family_zones.csv`\n",
    "  - Summary JSON to `../output/family_housing_summary.json`\n",
    "  - Distribution Plot to `../output/family_housing_distribution.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/family_housing_assessment.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/family_housing_assessment.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/family_housing_assessment.ipynb"
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