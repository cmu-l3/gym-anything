#!/bin/bash
echo "=== Setting up land_use_entropy_analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Ensure output directory exists and is clean
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
rm -f /home/ga/urbansim_projects/output/zone_entropy.csv
rm -f /home/ga/urbansim_projects/output/entropy_barplot.png
rm -f /home/ga/urbansim_projects/output/entropy_summary.json
rm -f /home/ga/urbansim_projects/notebooks/land_use_entropy.ipynb
chown -R ga:ga /home/ga/urbansim_projects

# Pre-compute ground truth for verification (hidden from agent)
mkdir -p /var/lib/urbansim_ground_truth
chmod 700 /var/lib/urbansim_ground_truth

echo "Computing ground truth logic..."
activate_venv
python << 'PYEOF'
import pandas as pd
import numpy as np
import json
import os

try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    buildings = store['buildings']
    parcels = store['parcels']
    store.close()

    # Determine building type column
    bt_col = None
    for col in ['building_type_id', 'building_type', 'land_use_type_id']:
        if col in buildings.columns:
            bt_col = col
            break

    # Determine zone linkage
    if 'zone_id' in buildings.columns:
        bldg_with_zone = buildings
    elif 'parcel_id' in buildings.columns and 'zone_id' in parcels.columns:
        bldg_with_zone = buildings.merge(
            parcels[['zone_id']], left_on='parcel_id', right_index=True, how='left'
        )
    else:
        # Try index-based join
        bldg_with_zone = buildings.merge(
            parcels[['zone_id']], left_index=True, right_index=True, how='left'
        )

    bldg_with_zone = bldg_with_zone.dropna(subset=['zone_id', bt_col])
    bldg_with_zone['zone_id'] = bldg_with_zone['zone_id'].astype(int)

    results = []
    for zone_id, group in bldg_with_zone.groupby('zone_id'):
        types = group[bt_col]
        counts = types.value_counts()
        total = counts.sum()
        proportions = counts / total
        
        entropy = -np.sum(proportions * np.log(proportions))
        
        K = len(counts)
        norm_entropy = entropy / np.log(K) if K > 1 else 0.0
        
        results.append({
            'zone_id': int(zone_id),
            'entropy': float(entropy),
            'normalized_entropy': float(norm_entropy),
            'total_buildings': int(total)
        })

    df = pd.DataFrame(results)

    # Filter zones with >= 10 buildings for ranking
    df_filtered = df[df['total_buildings'] >= 10].copy()
    most_diverse = df_filtered.nlargest(5, 'normalized_entropy')['zone_id'].tolist()
    least_diverse = df_filtered.nsmallest(5, 'normalized_entropy')['zone_id'].tolist()

    ground_truth = {
        'num_zones': len(df),
        'zone_entropy': {str(int(r['zone_id'])): {'entropy': r['entropy'], 'normalized_entropy': r['normalized_entropy']} for _, r in df.iterrows()},
        'most_diverse_zones': [int(z) for z in most_diverse],
        'least_diverse_zones': [int(z) for z in least_diverse],
        'mean_normalized_entropy': float(df['normalized_entropy'].mean()),
        'median_normalized_entropy': float(df['normalized_entropy'].median())
    }

    with open('/var/lib/urbansim_ground_truth/entropy_ground_truth.json', 'w') as f:
        json.dump(ground_truth, f, indent=2)

    print(f"Ground truth computed successfully: {len(df)} zones.")
except Exception as e:
    print(f"Failed to compute ground truth: {e}")
PYEOF

chmod 700 /var/lib/urbansim_ground_truth/entropy_ground_truth.json

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is running
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

# Dismiss dialogs and maximize Firefox window
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="