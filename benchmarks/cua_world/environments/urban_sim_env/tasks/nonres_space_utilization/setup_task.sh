#!/bin/bash
echo "=== Setting up nonres_space_utilization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure output directory exists
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Ensure real dataset is available
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: San Francisco UrbanSim dataset not found!"
    exit 1
fi

activate_venv

# Pre-compute ground truth securely, hidden from the agent
echo "Computing ground truth values..."
cat << 'EOF' > /tmp/compute_ground_truth.py
import pandas as pd
import json

try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', 'r')
    buildings = store['buildings']
    jobs = store['jobs']
    parcels = store['parcels']
    store.close()

    # Join zone_id to buildings
    b2 = buildings.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True)

    # Job counts per building
    job_counts = jobs.groupby('building_id').size().reset_index(name='job_count')

    # Join jobs to buildings
    b3 = b2.merge(job_counts, left_index=True, right_on='building_id', how='left')
    b3['job_count'] = b3['job_count'].fillna(0)

    # Aggregate by zone
    zone_stats = b3.groupby('zone_id').agg(
        total_non_res_sqft=('non_residential_sqft', 'sum'),
        total_jobs=('job_count', 'sum')
    ).reset_index()

    # Apply filters as specified in task
    valid_zones = zone_stats[(zone_stats['total_non_res_sqft'] > 0) & (zone_stats['total_jobs'] >= 1)].copy()
    valid_zones['sqft_per_job'] = valid_zones['total_non_res_sqft'] / valid_zones['total_jobs']
    
    # Sort
    valid_zones = valid_zones.sort_values('sqft_per_job', ascending=True)

    ground_truth = {
        "num_zones": len(valid_zones),
        "total_non_res_sqft": float(valid_zones['total_non_res_sqft'].sum()),
        "total_jobs": float(valid_zones['total_jobs'].sum()),
        "median_sqft_per_job": float(valid_zones['sqft_per_job'].median()),
        "top_5_zones": [int(x) for x in valid_zones['zone_id'].head(5).tolist()]
    }

    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(ground_truth, f)
        
    print("Ground truth generation successful.")
except Exception as e:
    print(f"Error generating ground truth: {e}")
EOF

python /tmp/compute_ground_truth.py
rm /tmp/compute_ground_truth.py

# Launch Jupyter Lab if not already running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Launch Firefox and navigate to the notebook directory
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs, maximize browser
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
maximize_firefox 2>/dev/null || true
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="