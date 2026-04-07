#!/bin/bash
set -e
echo "=== Setting up building vintage cohort analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file creation must happen AFTER this)
date +%s > /tmp/task_start_time.txt

# Clean previous task artifacts and prepare directories
rm -f /home/ga/urbansim_projects/output/aging_building_zones.csv
rm -f /home/ga/urbansim_projects/output/building_vintage_chart.png
rm -f /home/ga/urbansim_projects/notebooks/building_vintage_analysis.ipynb
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks

# Create an empty starting notebook
cat > /home/ga/urbansim_projects/notebooks/building_vintage_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Building Vintage Cohort Analysis\n",
    "\n",
    "Identify SF zones with the highest percentage of aging (pre-1940) building stock."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import matplotlib.pyplot as plt\n",
    "\n",
    "# Your code here..."
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

# Pre-compute ground truth for verification (hidden from agent)
mkdir -p /tmp/ground_truth
activate_venv
python3 << 'GROUND_TRUTH_EOF'
import pandas as pd
import json
import os

try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    buildings = store['buildings']
    parcels = store['parcels']
    store.close()

    # Determine zone column name (usually zone_id in parcels)
    zone_col = 'zone_id' if 'zone_id' in parcels.columns else 'zoning_id'

    # Join buildings with parcels to get zone_id
    if 'parcel_id' in buildings.columns:
        merged = buildings.merge(parcels[[zone_col]], left_on='parcel_id', right_index=True, how='left')
    else:
        merged = buildings.merge(parcels[[zone_col]], left_index=True, right_index=True, how='left')

    # Filter valid year_built
    valid = merged[(merged['year_built'] > 0) & (merged['year_built'].notna())].copy()

    # Compute pre-1940 stats per zone
    valid['pre_1940'] = (valid['year_built'] < 1940).astype(int)

    zone_stats = valid.groupby(zone_col).agg(
        total_buildings=('year_built', 'count'),
        pre_1940_count=('pre_1940', 'sum'),
        median_year_built=('year_built', 'median')
    ).reset_index()
    
    # Rename zone_col back to zone_id for uniformity
    zone_stats = zone_stats.rename(columns={zone_col: 'zone_id'})

    zone_stats['pre_1940_pct'] = (zone_stats['pre_1940_count'] / zone_stats['total_buildings'] * 100).round(2)

    # Filter zones with >= 20 buildings and get top 10
    zone_stats = zone_stats[zone_stats['total_buildings'] >= 20]
    top10 = zone_stats.nlargest(10, 'pre_1940_pct')

    # Save ground truth
    gt = {
        'top10_zone_ids': [int(z) for z in top10['zone_id'].tolist()],
        'top10_pre_1940_pcts': top10['pre_1940_pct'].tolist(),
        'total_valid_buildings': int(len(valid))
    }
    with open('/tmp/ground_truth/vintage_ground_truth.json', 'w') as f:
        json.dump(gt, f)
except Exception as e:
    # Failsafe if script errors due to exact schema differences
    with open('/tmp/ground_truth/vintage_ground_truth.json', 'w') as f:
        json.dump({"error": str(e)}, f)
GROUND_TRUTH_EOF

# Set proper permissions
chown -R ga:ga /home/ga/urbansim_projects
chmod 700 /tmp/ground_truth

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && DISPLAY=:1 jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is running
if ! is_firefox_running; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/building_vintage_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/building_vintage_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Focus, maximize, and prepare browser
maximize_firefox
focus_firefox
sleep 2

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="