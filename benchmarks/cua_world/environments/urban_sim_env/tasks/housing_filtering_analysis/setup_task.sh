#!/bin/bash
echo "=== Setting up housing filtering analysis task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Clean previous outputs
rm -f /home/ga/urbansim_projects/output/filtering_by_zone.csv
rm -f /home/ga/urbansim_projects/output/filtering_chart.png
rm -f /home/ga/urbansim_projects/output/filtering_report.txt
rm -f /home/ga/urbansim_projects/notebooks/filtering_analysis.ipynb

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv

# Create a starter notebook
cat > /home/ga/urbansim_projects/notebooks/filtering_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Housing Filtering Analysis\n",
    "\n",
    "Investigate the filtering hypothesis in San Francisco.\n",
    "\n",
    "## Requirements:\n",
    "- Load buildings, households, parcels from `../data/sanfran_public.h5`\n",
    "- Join data on building_id / parcel_id\n",
    "- Floor `year_built` to decades\n",
    "- Compute correlation between `year_built` and `income`\n",
    "- Compute zone-level filtering index (old vs new buildings)\n",
    "- Save CSV to `../output/filtering_by_zone.csv`\n",
    "- Save chart to `../output/filtering_chart.png`\n",
    "- Save report to `../output/filtering_report.txt`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/filtering_analysis.ipynb

# Pre-compute ground truth if possible (hidden from agent)
python -c "
import pandas as pd
import numpy as np
import json
import os

try:
    h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
    store = pd.HDFStore(h5_path, mode='r')

    buildings = store['/buildings']
    households = store['/households']
    parcels = store['/parcels']
    store.close()

    if 'building_id' not in households.columns:
        households = households.reset_index()
    if 'building_id' not in buildings.columns:
        buildings = buildings.reset_index()
    if 'parcel_id' not in buildings.columns and buildings.index.name == 'parcel_id':
        buildings = buildings.reset_index()
    if 'parcel_id' not in parcels.columns:
        parcels = parcels.reset_index()

    hb = households.merge(buildings[['building_id', 'year_built', 'parcel_id']].drop_duplicates('building_id'), on='building_id', how='inner')

    if 'zone_id' in buildings.columns:
        hb = hb.merge(buildings[['building_id', 'zone_id']].drop_duplicates('building_id'), on='building_id', how='left')
    else:
        hb = hb.merge(parcels[['parcel_id', 'zone_id']].drop_duplicates('parcel_id'), on='parcel_id', how='left')

    valid = hb[(hb['year_built'] > 0) & (hb['income'] > 0)].copy()
    corr = valid['year_built'].corr(valid['income'])

    valid['is_old'] = valid['year_built'] < 1960
    old_by_zone = valid[valid['is_old']].groupby('zone_id')['income'].median()
    new_by_zone = valid[~valid['is_old']].groupby('zone_id')['income'].median()
    common_zones = old_by_zone.index.intersection(new_by_zone.index)
    filtering_indices = old_by_zone[common_zones] / new_by_zone[common_zones]
    filtering_indices = filtering_indices.dropna()

    ground_truth = {
        'pearson_correlation': float(corr),
        'num_zones_analyzed': int(len(filtering_indices)),
        'median_filtering_index': float(filtering_indices.median())
    }
    with open('/tmp/filtering_ground_truth.json', 'w') as f:
        json.dump(ground_truth, f)
except Exception as e:
    with open('/tmp/filtering_ground_truth.json', 'w') as f:
        json.dump({'error': str(e)}, f)
" 2>/dev/null
chmod 666 /tmp/filtering_ground_truth.json 2>/dev/null || true

# Start Jupyter Lab
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/filtering_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/filtering_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="