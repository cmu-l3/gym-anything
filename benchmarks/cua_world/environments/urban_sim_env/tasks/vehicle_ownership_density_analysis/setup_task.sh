#!/bin/bash
echo "=== Setting up vehicle_ownership_density_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv

# Precompute ground truth to prevent gaming and verify results
echo "Precomputing ground truth..."
python -c "
import pandas as pd
import json

try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    hh = store['households']
    bld = store['buildings']
    pcl = store['parcels']
    store.close()
    
    # Households to zones
    hh_bld = hh.merge(bld[['parcel_id']], left_on='building_id', right_index=True)
    hh_zone = hh_bld.merge(pcl[['zone_id']], left_on='parcel_id', right_index=True)
    
    hh_agg = hh_zone.groupby('zone_id').agg(
        household_count=('cars', 'count'),  # Or any valid column for count
        avg_cars_per_hh=('cars', 'mean'),
        avg_income=('income', 'mean')
    )
    
    # Buildings to zones
    res_bld = bld[bld['residential_units'] > 0].copy()
    res_bld = res_bld.merge(pcl[['zone_id']], left_index=True, right_index=True)
    bld_agg = res_bld.groupby('zone_id').agg(
        avg_building_units=('residential_units', 'mean')
    )
    
    merged = hh_agg.merge(bld_agg, left_index=True, right_index=True)
    filtered = merged[merged['household_count'] >= 50]
    
    num_zones = len(filtered)
    corr = filtered['avg_building_units'].corr(filtered['avg_cars_per_hh'])
    
    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump({'num_zones_analyzed': num_zones, 'pearson_correlation': corr}, f)
        
except Exception as e:
    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"
chown ga:ga /tmp/ground_truth.json

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/parking_reform_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Parking Reform Analysis: Vehicle Ownership vs. Density\n",
    "\n",
    "Analyze the relationship between residential density and household vehicle ownership across SF zones.\n",
    "\n",
    "## Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` tables from `../data/sanfran_public.h5`\n",
    "- Compute zone-level household metrics: `household_count`, `avg_cars_per_hh`, `avg_income`\n",
    "- Compute zone-level building density metrics (for residential buildings only): `avg_building_units`\n",
    "- Merge household and building metrics on `zone_id`\n",
    "- Filter to keep only zones with `household_count` >= 50\n",
    "- Compute Pearson correlation between `avg_building_units` and `avg_cars_per_hh`\n",
    "- Save CSV to `../output/zone_vehicle_metrics.csv`\n",
    "- Save correlation JSON to `../output/correlation.json`\n",
    "- Save bubble chart to `../output/auto_ownership_chart.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/parking_reform_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open notebook in Firefox
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/parking_reform_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/parking_reform_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="