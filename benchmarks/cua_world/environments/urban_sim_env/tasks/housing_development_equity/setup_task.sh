#!/bin/bash
echo "=== Setting up housing_development_equity task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time (anti-gaming)
date +%s > /home/ga/.task_start_time

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Households: {len(hh)} rows')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(parcels)} rows')
assert len(hh) > 100, 'Not enough household records'
print('Data verification passed')
"

# Prepare the starter notebook
cat > /home/ga/urbansim_projects/notebooks/development_equity.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Housing Development Equity Analysis\n",
    "\n",
    "Analyze the equity implications of recent housing development by exploring the relationship between new housing construction and neighborhood income levels.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings`, `parcels`, and `households` from `../data/sanfran_public.h5`\n",
    "- Compute housing metrics per zone: `total_units`, `recent_units` (year_built >= 2000)\n",
    "- Compute income metrics per zone: `median_income`, `household_count`\n",
    "- Filter out outliers: KEEP ONLY zones where `total_units >= 50` AND `household_count >= 20`\n",
    "- Classify into 4 quartiles: use `pd.qcut` on `median_income` with labels `[1, 2, 3, 4]`\n",
    "- Save zone-level DataFrame to `../output/zone_development_equity.csv`\n",
    "- Aggregate by quartile to get total/recent units and `pct_of_citywide_recent_units`\n",
    "- Save quartile summary to `../output/quartile_absorption.csv`\n",
    "- Save bar chart of recent units by quartile to `../output/recent_units_by_income.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/development_equity.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is pointing to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/development_equity.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/development_equity.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss popups and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="