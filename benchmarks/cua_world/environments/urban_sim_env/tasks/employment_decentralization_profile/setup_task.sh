#!/bin/bash
echo "=== Setting up employment_decentralization_profile task ==="

source /workspace/scripts/task_utils.sh

# Create output and notebooks directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time

# Verify HDF5 data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv

# Pre-compute ground truth silently to prevent hardcoding/gaming
python << 'PYEOF'
import pandas as pd
import numpy as np
import json
import os

try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    jobs = store['jobs']
    buildings = store['buildings']
    parcels = store['parcels']
    store.close()

    # Join jobs -> buildings -> parcels
    df = jobs.join(buildings, on='building_id', rsuffix='_bld')
    if 'parcel_id' in df.columns:
        df = df.join(parcels, on='parcel_id', rsuffix='_pcl')
        
    # Clean data
    df = df.dropna(subset=['x', 'y'])
    df = df[(df['x'] != 0) & (df['y'] != 0)]
    
    total_valid = len(df)

    # Identify CBD
    zone_job_counts = df.groupby('zone_id').size()
    cbd_zone = int(zone_job_counts.idxmax())
    cbd_jobs = df[df['zone_id'] == cbd_zone]
    cbd_x = float(cbd_jobs['x'].mean())
    cbd_y = float(cbd_jobs['y'].mean())

    # Calculate Distances
    df['dist_to_cbd'] = np.sqrt((df['x'] - cbd_x)**2 + (df['y'] - cbd_y)**2)

    # Top Sectors
    sector_counts = df.groupby('sector_id').size().sort_values(ascending=False)
    top_3 = sector_counts.head(3).index.tolist()

    sector_stats = {}
    for s in top_3:
        s_jobs = df[df['sector_id'] == s]
        sector_stats[str(int(s))] = {
            'total_jobs': int(len(s_jobs)),
            'median_dist': float(s_jobs['dist_to_cbd'].median()),
            'p75_dist': float(s_jobs['dist_to_cbd'].quantile(0.75))
        }

    gt = {
        'cbd_zone_id': cbd_zone,
        'cbd_x': cbd_x,
        'cbd_y': cbd_y,
        'total_valid_jobs_citywide': total_valid,
        'top_3_sectors': [int(s) for s in top_3],
        'sector_stats': sector_stats
    }

    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(gt, f, indent=2)
    
    # Hide ground truth from agent
    os.chmod('/tmp/ground_truth.json', 0o600)
    print("Ground truth successfully generated.")
except Exception as e:
    print(f"Error generating ground truth: {e}")
PYEOF

# Create the starter notebook
cat > /home/ga/urbansim_projects/notebooks/employment_decentralization.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Employment Decentralization and Job Sprawl Analysis\n",
    "\n",
    "Analyze the spatial distribution of jobs in San Francisco relative to the Central Business District (CBD).\n",
    "\n",
    "## Requirements:\n",
    "- Load `jobs`, `buildings`, and `parcels` tables from `../data/sanfran_public.h5`.\n",
    "- Join the tables to get coordinates (`x`, `y`) and `zone_id` for every job.\n",
    "- Clean data: drop missing or exactly 0.0 coordinates.\n",
    "- **Find the CBD**: Identify the `zone_id` with the most total jobs. Calculate the mean `x` and `y` of jobs strictly in that zone.\n",
    "- Calculate Euclidean distance from every job to the CBD.\n",
    "- For the **top 3 employment sectors** (by total jobs), calculate the median distance and 75th percentile distance to the CBD.\n",
    "- Export results to JSON, CSV, and PNG as specified in the task description."
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
chown ga:ga /home/ga/urbansim_projects/notebooks/employment_decentralization.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/employment_decentralization.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/employment_decentralization.ipynb"
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