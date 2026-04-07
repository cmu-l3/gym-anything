#!/bin/bash
set -e
echo "=== Setting up job-housing balance analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming timestamp)
date +%s > /home/ga/.task_start_time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks

# Clean previous task artifacts if any
rm -f /home/ga/urbansim_projects/output/zone_job_housing_balance.csv
rm -f /home/ga/urbansim_projects/output/job_housing_summary.json
rm -f /home/ga/urbansim_projects/output/job_housing_balance_chart.png
rm -f /home/ga/urbansim_projects/notebooks/job_housing_balance.ipynb

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found. Attempting to copy from install..."
    cp /opt/urbansim_data/sanfran_public.h5 /home/ga/urbansim_projects/data/ || exit 1
fi

# Compute Ground Truth (Hidden from Agent)
echo "Computing ground truth..."
activate_venv
python3 << 'PYEOF'
import pandas as pd
import numpy as np
import json

h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
store = pd.HDFStore(h5_path, 'r')

buildings = store['/buildings']
parcels = store['/parcels']
households = store['/households']
jobs = store['/jobs']
store.close()

# Joins
bldg_zone = buildings[['parcel_id']].merge(
    parcels[['zone_id']], left_on='parcel_id', right_index=True, how='left'
)

hh_zone = households[['building_id']].merge(
    bldg_zone[['zone_id']], left_on='building_id', right_index=True, how='inner'
)
hh_per_zone = hh_zone.groupby('zone_id').size()

jobs_zone = jobs[['building_id']].merge(
    bldg_zone[['zone_id']], left_on='building_id', right_index=True, how='inner'
)
jobs_per_zone = jobs_zone.groupby('zone_id').size()

bldg_with_zone = buildings[['parcel_id', 'residential_units']].merge(
    parcels[['zone_id']], left_on='parcel_id', right_index=True, how='left'
)
units_per_zone = bldg_with_zone.groupby('zone_id')['residential_units'].sum()

# Aggregate
all_zones = sorted(parcels['zone_id'].dropna().unique())
zone_df = pd.DataFrame(index=all_zones)
zone_df.index.name = 'zone_id'
zone_df['total_jobs'] = jobs_per_zone.reindex(zone_df.index, fill_value=0).astype(int)
zone_df['total_households'] = hh_per_zone.reindex(zone_df.index, fill_value=0).astype(int)
zone_df['residential_units'] = units_per_zone.reindex(zone_df.index, fill_value=0).astype(int)

# Ratios
zone_df['jobs_housing_ratio'] = np.where(
    zone_df['total_households'] > 0,
    zone_df['total_jobs'] / zone_df['total_households'],
    np.nan
)

# Classifications
def classify(row):
    if row['total_households'] == 0 and row['total_jobs'] == 0:
        return 'no_activity'
    if row['total_households'] == 0 and row['total_jobs'] > 0:
        return 'job_rich'
    ratio = row['jobs_housing_ratio']
    if ratio > 3.0:
        return 'job_rich'
    elif ratio < 0.5:
        return 'housing_rich'
    else:
        return 'balanced'

zone_df['classification'] = zone_df.apply(classify, axis=1)

# Summary logic
total_hh = zone_df['total_households'].sum()
total_jobs = zone_df['total_jobs'].sum()
citywide_ratio = float(total_jobs / total_hh) if total_hh > 0 else None

gt = {
    'total_zones': len(zone_df),
    'job_rich_zones': int((zone_df['classification'] == 'job_rich').sum()),
    'balanced_zones': int((zone_df['classification'] == 'balanced').sum()),
    'housing_rich_zones': int((zone_df['classification'] == 'housing_rich').sum()),
    'citywide_ratio': citywide_ratio,
    'zone_ratios': {str(int(idx)): float(row['jobs_housing_ratio']) if not np.isnan(row['jobs_housing_ratio']) else None for idx, row in zone_df.iterrows()},
    'zone_classifications': {str(int(idx)): row['classification'] for idx, row in zone_df.iterrows()}
}

valid = zone_df.dropna(subset=['jobs_housing_ratio'])
if len(valid) > 0:
    gt['most_job_rich_zone'] = int(valid['jobs_housing_ratio'].idxmax())
    gt['most_housing_rich_zone'] = int(valid['jobs_housing_ratio'].idxmin())
else:
    gt['most_job_rich_zone'] = None
    gt['most_housing_rich_zone'] = None

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f)
PYEOF

chmod 600 /tmp/ground_truth.json
chown -R ga:ga /home/ga/urbansim_projects

# Start Jupyter Lab if not running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is open to the workspace
if ! is_firefox_running; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
maximize_firefox
focus_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="