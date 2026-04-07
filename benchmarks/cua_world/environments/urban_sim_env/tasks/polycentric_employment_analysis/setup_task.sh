#!/bin/bash
set -e
echo "=== Setting up Polycentric Employment Analysis Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects

# Remove any previous artifacts
rm -f /home/ga/urbansim_projects/output/zone_employment_density.csv
rm -f /home/ga/urbansim_projects/output/subcenter_ranking.csv
rm -f /home/ga/urbansim_projects/output/zipf_results.json
rm -f /home/ga/urbansim_projects/output/ranksize_plot.png
rm -f /home/ga/urbansim_projects/notebooks/polycentric_analysis.ipynb

# Verify the HDF5 data file exists
DATA_FILE="/home/ga/urbansim_projects/data/sanfran_public.h5"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file $DATA_FILE not found!"
    exit 1
fi

# Calculate Ground Truth silently
echo "Pre-calculating ground truth metrics..."
source /opt/urbansim_env/bin/activate
python3 << 'GROUND_TRUTH_EOF'
import pandas as pd
import numpy as np
import json
import warnings
warnings.filterwarnings('ignore')

try:
    # Load data
    jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
    buildings = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')

    # Join jobs -> buildings -> parcels
    j_b = jobs.merge(buildings[['parcel_id']], left_on='building_id', right_index=True, how='inner')
    j_b_p = j_b.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True, how='inner')
    j_b_p = j_b_p.dropna(subset=['zone_id'])

    total_employment = len(j_b_p)

    # Aggregate
    zone_emp = j_b_p.groupby('zone_id').size().reset_index(name='total_employment')
    parcels_per_zone = parcels.groupby('zone_id').size().reset_index(name='num_parcels')

    zone_data = zone_emp.merge(parcels_per_zone, on='zone_id', how='left')
    zone_data['employment_density'] = zone_data['total_employment'] / zone_data['num_parcels']

    # Sub-centers
    threshold = zone_data['employment_density'].mean() + zone_data['employment_density'].std()
    zone_data['is_subcenter'] = zone_data['employment_density'] > threshold

    subcenters = zone_data[zone_data['is_subcenter']].sort_values('total_employment', ascending=False).reset_index(drop=True)
    subcenters['rank'] = range(1, len(subcenters) + 1)
    num_subcenters = len(subcenters)

    # Zipf regression
    log_rank = np.log(subcenters['rank'].values)
    log_emp = np.log(subcenters['total_employment'].values)
    
    coeffs = np.polyfit(log_emp, log_rank, 1)
    zipf_exponent = coeffs[0]
    
    predicted = np.polyval(coeffs, log_emp)
    ss_res = np.sum((log_rank - predicted) ** 2)
    ss_tot = np.sum((log_rank - np.mean(log_rank)) ** 2)
    r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0.0

    # Save
    gt = {
        'total_citywide_employment': int(total_employment),
        'num_zones': int(len(zone_data)),
        'num_subcenters': int(num_subcenters),
        'zipf_exponent': float(zipf_exponent),
        'r_squared': float(r_squared),
        'density_threshold': float(threshold)
    }

    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(gt, f)
    print("Ground truth saved successfully.")
except Exception as e:
    print(f"Error computing ground truth: {e}")
GROUND_TRUTH_EOF

# Hide ground truth from agent
chmod 600 /tmp/ground_truth.json

# Start Jupyter Lab if not running
if ! pgrep -f "jupyter-lab" > /dev/null; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    
    # Wait for Jupyter
    for i in {1..30}; do
        if curl -s http://localhost:8888/api > /dev/null 2>&1; then
            break
        fi
        sleep 2
    done
fi

# Start Firefox
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Close any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="