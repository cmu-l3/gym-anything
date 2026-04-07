#!/bin/bash
echo "=== Setting up spatial_autocorrelation_analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create output directory
mkdir -p /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/output

# Install required spatial statistics packages into the virtualenv
echo "Installing libpysal and esda..."
su - ga -c "source /opt/urbansim_env/bin/activate && pip install libpysal esda splot --quiet" || true

# Pre-compute ground truth safely without exposing it to the agent
mkdir -p /tmp/ground_truth
cat << 'EOF' > /tmp/compute_ground_truth.py
import pandas as pd
import geopandas as gpd
import json
import warnings
warnings.filterwarnings('ignore')

gt = {}
try:
    buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    
    # Identify proper zone and residential units columns
    zone_col = next((c for c in buildings.columns if 'zone_id' in c.lower()), None)
    res_col = next((c for c in buildings.columns if 'residential_units' in c.lower()), None)
    
    if zone_col and res_col:
        zone_units = buildings.groupby(zone_col)[res_col].sum().reset_index()
        zones = gpd.read_file('/home/ga/urbansim_projects/data/zones.json')
        
        # Find best matching join column dynamically
        best_match = 0
        merge_col = None
        for col in zones.columns:
            if col == 'geometry': continue
            z_vals = set(zones[col].astype(str))
            b_vals = set(zone_units[zone_col].astype(str))
            matches = len(z_vals.intersection(b_vals))
            if matches > best_match:
                best_match = matches
                merge_col = col
                
        if merge_col and best_match > 10:
            zones[merge_col] = zones[merge_col].astype(str)
            zone_units[zone_col] = zone_units[zone_col].astype(str)
            merged = zones.merge(zone_units, left_on=merge_col, right_on=zone_col, how='left')
            merged[res_col] = merged[res_col].fillna(0)
            
            from libpysal.weights import Queen
            w = Queen.from_dataframe(merged)
            w.transform = 'r'
            
            from esda.moran import Moran
            y = merged[res_col].values
            mi = Moran(y, w, permutations=999)
            
            gt = {
                'global_morans_i': float(mi.I),
                'global_p_value': float(mi.p_sim),
                'num_zones': int(len(merged))
            }
        else:
            gt = {'error': 'No matching join column found between zones and buildings'}
    else:
        gt = {'error': 'Required columns not found in buildings table'}
except Exception as e:
    gt = {'error': str(e)}

with open('/tmp/ground_truth/spatial_truth.json', 'w') as f:
    json.dump(gt, f)
EOF

/opt/urbansim_env/bin/python /tmp/compute_ground_truth.py
chmod 700 /tmp/ground_truth
rm /tmp/compute_ground_truth.py

# Create a starter notebook
cat > /home/ga/urbansim_projects/notebooks/spatial_autocorrelation.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Spatial Autocorrelation Analysis\n",
    "\n",
    "Analyze residential density clustering patterns across San Francisco.\n",
    "\n",
    "## Task Requirements:\n",
    "- Load `buildings` from `../data/sanfran_public.h5` and aggregate `residential_units` per `zone_id`\n",
    "- Load zone polygons from `../data/zones.json` using GeoPandas\n",
    "- Merge density data with zone geometries (fill 0 for missing)\n",
    "- Build Queen contiguity weights\n",
    "- Compute Global and Local Moran's I\n",
    "- Classify spatial clusters (HH, LL, HL, LH, NS)\n",
    "- Export results to:\n",
    "  - `../output/lisa_results.csv`\n",
    "  - `../output/lisa_map.png`\n",
    "  - `../output/spatial_summary.json`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/spatial_autocorrelation.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is open to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/spatial_autocorrelation.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/spatial_autocorrelation.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Maximize and take initial screenshot
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="