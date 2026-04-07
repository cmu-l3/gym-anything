#!/bin/bash
echo "=== Setting up transit corridor catchment analysis task ==="

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

activate_venv

# Pre-calculate Ground Truth securely (hidden from agent)
echo "Pre-calculating exact ground truth..."
cat > /tmp/generate_gt.py << 'EOF'
import pandas as pd
import json
import numpy as np
import os
from shapely.geometry import Point, LineString

try:
    store = pd.HDFStore('/opt/urbansim_data/sanfran_public.h5', mode='r')
    parcels = store['parcels']
    buildings = store['buildings']
    households = store['households']
    jobs = store['jobs']
    store.close()

    # Clean coordinates
    parcels = parcels.dropna(subset=['x', 'y'])
    parcels = parcels[(parcels.x != 0) & (parcels.y != 0)]

    # Sort to resolve ties definitively
    parcels_sorted_west = parcels.sort_values(by=['x', 'y'])
    parcels_sorted_east = parcels.sort_values(by=['x', 'y'], ascending=[False, True])

    p_west = parcels_sorted_west.iloc[0]
    p_east = parcels_sorted_east.iloc[0]

    # Buffer logic
    x_width = p_east.x - p_west.x
    buffer_dist = x_width * 0.05

    line = LineString([(p_west.x, p_west.y), (p_east.x, p_east.y)])
    
    # Calculate distance for each parcel
    # (Using pandas apply is safe here, ~150k parcels might take 10-15s)
    parcels['dist'] = parcels.apply(lambda row: Point(row.x, row.y).distance(line), axis=1)
    catchment = parcels[parcels.dist <= buffer_dist]

    # Function to get metrics
    def get_metrics(parcel_df):
        num_parcels = len(parcel_df)
        bld = buildings[buildings.parcel_id.isin(parcel_df.index)]
        res_units = bld.residential_units.sum() if 'residential_units' in bld else 0
        
        hh = households[households.building_id.isin(bld.index)]
        num_hh = len(hh)
        pop = hh.persons.sum() if 'persons' in hh else 0
        
        jb = jobs[jobs.building_id.isin(bld.index)]
        num_jobs = len(jb)
        
        return num_parcels, float(res_units), num_hh, float(pop), num_jobs

    cw_parcels, cw_units, cw_hh, cw_pop, cw_jobs = get_metrics(parcels)
    c_parcels, c_units, c_hh, c_pop, c_jobs = get_metrics(catchment)

    gt = {
        "corridor": {
            "p_west": {"x": float(p_west.x), "y": float(p_west.y)},
            "p_east": {"x": float(p_east.x), "y": float(p_east.y)}
        },
        "buffer_distance": float(buffer_dist),
        "metrics": {
            "parcels": {"citywide": cw_parcels, "catchment": c_parcels, "share_pct": (c_parcels/cw_parcels)*100 if cw_parcels else 0},
            "res_units": {"citywide": cw_units, "catchment": c_units, "share_pct": (c_units/cw_units)*100 if cw_units else 0},
            "households": {"citywide": cw_hh, "catchment": c_hh, "share_pct": (c_hh/cw_hh)*100 if cw_hh else 0},
            "population": {"citywide": cw_pop, "catchment": c_pop, "share_pct": (c_pop/cw_pop)*100 if cw_pop else 0},
            "jobs": {"citywide": cw_jobs, "catchment": c_jobs, "share_pct": (c_jobs/cw_jobs)*100 if cw_jobs else 0}
        }
    }

    with open('/tmp/ground_truth_catchment.json', 'w') as f:
        json.dump(gt, f)

except Exception as e:
    with open('/tmp/ground_truth_catchment.json', 'w') as f:
        json.dump({"error": str(e)}, f)
EOF

python /tmp/generate_gt.py
chmod 600 /tmp/ground_truth_catchment.json # Hide from standard ga user inspection
rm /tmp/generate_gt.py
echo "Ground truth generated."

# Create empty notebook for the task
cat > /home/ga/urbansim_projects/notebooks/brt_catchment_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Proposed Transit Corridor Catchment Analysis\n",
    "\n",
    "Calculate the transit-oriented development baseline for a proposed East-West Bus Rapid Transit (BRT) corridor.\n",
    "\n",
    "## Requirements:\n",
    "- Load `parcels`, `buildings`, `households`, and `jobs` from `../data/sanfran_public.h5`\n",
    "- Clean coords (drop NaN or 0.0)\n",
    "- Define corridor line from westernmost to easternmost parcel\n",
    "- Buffer by 5% of the X-axis width\n",
    "- Calculate metrics and export structured JSON to `../output/catchment_metrics.json`\n",
    "- Save scatter plot map to `../output/catchment_map.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/brt_catchment_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/brt_catchment_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/brt_catchment_analysis.ipynb"
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