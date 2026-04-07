#!/bin/bash
echo "=== Setting up household_size_distribution_analysis task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

date +%s > /home/ga/.task_start_time

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
assert 'persons' in hh.columns, 'persons column missing'
assert 'zone_id' in parcels.columns, 'zone_id column missing'
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/household_size_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Household Size Distribution Analysis\n",
    "\n",
    "Analyze household sizes across SF zones to identify family vs single-occupant neighborhoods.\n",
    "\n",
    "## Requirements:\n",
    "- Load households, buildings, and parcels from `../data/sanfran_public.h5`\n",
    "- Join tables to get `zone_id` for each household\n",
    "- Categorize households into '1-person', '2-person', and '3+ person'\n",
    "- Compute metrics by zone (total_households, avg_persons, counts, and percentages)\n",
    "- Filter for zones with >= 50 total_households\n",
    "- Identify the top 5 zones with highest `pct_3plus_person` and top 5 with highest `pct_1_person`\n",
    "- Save filtered dataframe to `../output/zone_household_sizes.csv`\n",
    "- Save visualization for the 10 identified zones to `../output/family_vs_single_zones.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/household_size_analysis.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/household_size_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/household_size_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="