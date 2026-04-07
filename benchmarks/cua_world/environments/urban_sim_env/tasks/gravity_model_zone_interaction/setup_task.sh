#!/bin/bash
echo "=== Setting up gravity model zone interaction task ==="

# Record task start time
date +%s > /home/ga/.task_start_time

# Source utilities
source /workspace/scripts/task_utils.sh

# Activate virtualenv
activate_venv

# Ensure output directory exists
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Remove any previous task artifacts
rm -f /home/ga/urbansim_projects/output/zone_interactions_top20.csv
rm -f /home/ga/urbansim_projects/output/zone_interaction_potential.csv
rm -f /home/ga/urbansim_projects/output/interaction_heatmap.png
rm -f /home/ga/urbansim_projects/notebooks/gravity_model.ipynb

# Pre-compute ground truth
echo "Computing ground truth..."
cat > /tmp/compute_ground_truth.py << 'PYEOF'
import pandas as pd
import numpy as np
import json

DATA_PATH = "/home/ga/urbansim_projects/data/sanfran_public.h5"

try:
    store = pd.HDFStore(DATA_PATH, mode='r')
    buildings = store['buildings']
    parcels = store['parcels']
    households = store['households']
    jobs = store['jobs']
    store.close()
    
    # Determine column names
    bld_parcel_col = 'parcel_id' if 'parcel_id' in buildings.columns else ('parcel_id' if buildings.index.name == 'parcel_id' else None)
    if bld_parcel_col is None and buildings.index.name == 'parcel_id': buildings = buildings.reset_index()
    
    parcel_zone_col = 'zone_id'
    hh_bld_col = 'building_id' if 'building_id' in households.columns else households.index.name
    hh_persons_col = 'persons'
    job_bld_col = 'building_id' if 'building_id' in jobs.columns else jobs.index.name
    
    # Households to zones
    bld_parcel_zone = buildings[[bld_parcel_col]].copy()
    bld_parcel_zone = bld_parcel_zone.merge(
        parcels[[parcel_zone_col]], left_on=bld_parcel_col, right_index=True, how='inner'
    )
    
    hh_with_zone = households[[hh_persons_col]].copy()
    if hh_bld_col in households.columns:
        hh_with_zone[hh_bld_col] = households[hh_bld_col]
    else:
        hh_with_zone[hh_bld_col] = households.index
        
    hh_with_zone = hh_with_zone.merge(
        bld_parcel_zone[[parcel_zone_col]], left_on=hh_bld_col, right_index=True, how='inner'
    )
    zone_pop = hh_with_zone.groupby(parcel_zone_col)[hh_persons_col].sum()
    
    # Jobs to zones
    jobs_copy = jobs[[]].copy()
    if job_bld_col in jobs.columns:
        jobs_copy[job_bld_col] = jobs[job_bld_col]
    else:
        jobs_copy[job_bld_col] = jobs.index
        
    jobs_with_zone = jobs_copy.merge(
        bld_parcel_zone[[parcel_zone_col]], left_on=job_bld_col, right_index=True, how='inner'
    )
    zone_emp = jobs_with_zone.groupby(parcel_zone_col).size()
    
    # Zone centroids
    zone_centroids = parcels.groupby(parcel_zone_col)[['x', 'y']].mean()
    
    # Common zones
    common_zones = sorted(
        set(zone_pop[zone_pop > 0].index) &
        set(zone_emp[zone_emp > 0].index) &
        set(zone_centroids.dropna().index)
    )
    
    pop_arr = zone_pop.reindex(common_zones, fill_value=0).values.astype(float)
    emp_arr = zone_emp.reindex(common_zones, fill_value=0).values.astype(float)
    coords = zone_centroids.loc[common_zones][['x', 'y']].values.astype(float)
    
    n = len(common_zones)
    diff = coords[:, np.newaxis, :] - coords[np.newaxis, :, :]
    dist_matrix = np.sqrt((diff ** 2).sum(axis=-1))
    
    beta = 2.0
    interactions = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            if i != j and dist_matrix[i, j] > 0:
                interactions[i, j] = (pop_arr[i] * emp_arr[j]) / (dist_matrix[i, j] ** beta)
                
    pairs = []
    for i in range(n):
        for j in range(n):
            if i != j and interactions[i, j] > 0:
                pairs.append({
                    'origin_zone': int(common_zones[i]),
                    'destination_zone': int(common_zones[j]),
                    'interaction': float(interactions[i, j])
                })
    pairs.sort(key=lambda x: x['interaction'], reverse=True)
    top20 = pairs[:20]
    
    zone_potential = {}
    for i in range(n):
        zone_potential[int(common_zones[i])] = {
            'population': int(pop_arr[i]),
            'employment': int(emp_arr[i]),
            'interaction_potential': float(interactions[i, :].sum())
        }
    sorted_zones = sorted(zone_potential.items(), key=lambda x: x[1]['interaction_potential'], reverse=True)
    
    ground_truth = {
        'num_zones': n,
        'total_population': int(zone_pop.sum()),
        'total_employment': int(zone_emp.sum()),
        'top20_pairs': top20,
        'top5_pairs': top20[:5],
        'top10_zones': [
            {
                'zone_id': int(z[0]),
                'population': z[1]['population'],
                'employment': z[1]['employment'],
                'interaction_potential': z[1]['interaction_potential']
            }
            for z in sorted_zones[:10]
        ]
    }
    
    with open('/tmp/gravity_ground_truth.json', 'w') as f:
        json.dump(ground_truth, f)

except Exception as e:
    with open('/tmp/gravity_ground_truth.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

/opt/urbansim_env/bin/python /tmp/compute_ground_truth.py
rm -f /tmp/compute_ground_truth.py

# Protect ground truth from agent
chmod 600 /tmp/gravity_ground_truth.json

# Create empty notebook
cat > /home/ga/urbansim_projects/notebooks/gravity_model.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Gravity Model Zone Interaction Analysis\n",
    "\n",
    "Build a gravity model of inter-zone spatial interactions for San Francisco.\n",
    "\n",
    "## Requirements:\n",
    "- Load data from `../data/sanfran_public.h5`\n",
    "- Link households & jobs to zones to compute population & employment per zone\n",
    "- Compute zone centroids and distance matrix\n",
    "- Calculate gravity model: $Interaction_{ij} = \\frac{Pop_i \\times Emp_j}{Dist_{ij}^{2.0}}$\n",
    "- Save top 20 interactions to `../output/zone_interactions_top20.csv`\n",
    "- Compute zone potential and save to `../output/zone_interaction_potential.csv`\n",
    "- Save interaction heatmap to `../output/interaction_heatmap.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/gravity_model.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is running
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/gravity_model.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/gravity_model.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
maximize_firefox
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Gravity model task setup complete ==="