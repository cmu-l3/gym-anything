#!/bin/bash
echo "=== Setting up housing_affordability_analysis task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /home/ga/.task_start_time

# Create expected directories and set permissions
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Compute ground truth metrics safely using the container's environment (hidden from agent)
activate_venv
python -c "
import pandas as pd
import json
import numpy as np
import warnings
warnings.filterwarnings('ignore')

try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    households = store['/households'].copy()
    buildings = store['/buildings'].copy()
    parcels = store['/parcels'].copy()
    store.close()
    
    # Get parcel_id for households via building_id
    if 'building_id' in households.columns:
        hh = households.join(buildings[['parcel_id']], on='building_id')
    else:
        hh = households.copy()
        hh['parcel_id'] = np.nan
        
    # Get zone_id for households via parcel_id
    if 'zone_id' in parcels.columns:
        hh = hh.join(parcels[['zone_id']], on='parcel_id')
    else:
        hh['zone_id'] = np.nan
        
    # Get zone_id for buildings via parcel_id
    bld = buildings.join(parcels[['zone_id']], on='parcel_id')
    
    # Calculate zone metrics
    zone_income = hh.groupby('zone_id')['income'].median()
    bld_pos = bld[bld['residential_sales_price'] > 0]
    zone_price = bld_pos.groupby('zone_id')['residential_sales_price'].median()
    zone_count = hh.groupby('zone_id').size()
    
    res = pd.DataFrame({
        'median_income': zone_income, 
        'median_price': zone_price, 
        'num_households': zone_count
    }).dropna()
    res['price_to_income_ratio'] = res['median_price'] / res['median_income']
    res = res[res['num_households'] >= 10]
    
    gt = {
        'num_zones': int(len(res)),
        'median_ratio': float(res['price_to_income_ratio'].median()),
        'mean_ratio': float(res['price_to_income_ratio'].mean())
    }
except Exception as e:
    gt = {'error': str(e), 'num_zones': 0, 'median_ratio': 0, 'mean_ratio': 0}

with open('/tmp/affordability_ground_truth.json', 'w') as f:
    json.dump(gt, f)
"
chmod 644 /tmp/affordability_ground_truth.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is running
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Dismiss any Firefox popups and maximize window
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot of correct starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="