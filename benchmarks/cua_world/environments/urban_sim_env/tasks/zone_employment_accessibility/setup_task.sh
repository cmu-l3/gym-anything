#!/bin/bash
set -e
echo "=== Setting up zone_employment_accessibility task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Activate virtualenv
source /opt/urbansim_env/bin/activate

# Ensure workspace exists
mkdir -p /home/ga/urbansim_projects/notebooks
mkdir -p /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects

# Clean any previous task artifacts
rm -f /home/ga/urbansim_projects/notebooks/employment_accessibility.ipynb
rm -f /home/ga/urbansim_projects/output/zone_accessibility.csv
rm -f /home/ga/urbansim_projects/output/accessibility_map.png
rm -f /home/ga/urbansim_projects/output/accessibility_summary.txt

# Create a blank starting notebook
cat > /home/ga/urbansim_projects/notebooks/employment_accessibility.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Employment Accessibility Analysis\n",
    "\n",
    "Identify 'employment access deserts' by computing K=10 nearest-neighbor accessibility for San Francisco zones."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import numpy as np\n",
    "import matplotlib.pyplot as plt\n",
    "\n",
    "DATA_PATH = '../data/sanfran_public.h5'\n",
    "# Start your analysis here..."
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
chown ga:ga /home/ga/urbansim_projects/notebooks/employment_accessibility.ipynb

# Compute ground truth (hidden from agent)
echo "Computing ground truth..."
cat > /tmp/compute_ground_truth.py << 'PYEOF'
import pandas as pd
import numpy as np
import json
import warnings
warnings.filterwarnings('ignore')

DATA_PATH = '/home/ga/urbansim_projects/data/sanfran_public.h5'

try:
    # Load tables
    store = pd.HDFStore(DATA_PATH, mode='r')
    buildings = store['buildings']
    parcels = store['parcels']
    jobs = store['jobs']
    store.close()

    # Join jobs -> buildings -> parcels to get zone_id
    if 'building_id' in jobs.columns:
        job_bld = jobs[['building_id']].copy()
    else:
        # Fallback if building_id is index or named differently
        job_bld = jobs.reset_index()[['building_id']] if 'building_id' in jobs.index.names else jobs.iloc[:, :1]
        job_bld.columns = ['building_id']

    # Merge with buildings
    bld_parcels = buildings[['parcel_id']].copy()
    merged = job_bld.merge(bld_parcels, left_on='building_id', right_index=True, how='inner')

    # Merge with parcels
    parcel_cols = parcels[['zone_id', 'x', 'y']].copy()
    merged = merged.merge(parcel_cols, left_on='parcel_id', right_index=True, how='inner')

    # Drop missing
    merged = merged.dropna(subset=['zone_id', 'x', 'y'])
    merged['zone_id'] = merged['zone_id'].astype(int)

    total_jobs_mapped = len(merged)

    # Jobs per zone
    jobs_per_zone = merged.groupby('zone_id').size()

    # Zone centroids from parcels
    valid_parcels = parcels[parcels['x'].notna() & parcels['y'].notna()].copy()
    valid_parcels['zone_id'] = valid_parcels['zone_id'].astype(int)
    zone_centroids = valid_parcels.groupby('zone_id')[['x', 'y']].mean()

    # Common zones
    all_zones = sorted(zone_centroids.index.tolist())
    jobs_reindexed = jobs_per_zone.reindex(all_zones, fill_value=0)

    # Compute pairwise distances
    coords = zone_centroids.loc[all_zones][['x', 'y']].values
    diff_x = coords[:, 0:1] - coords[:, 0:1].T
    diff_y = coords[:, 1:2] - coords[:, 1:2].T
    dist_matrix = np.sqrt(diff_x**2 + diff_y**2)

    K = 10
    results = {}
    for i, zone_id in enumerate(all_zones):
        # Sort by distance, take K+1 nearest (including self at distance 0)
        nearest_indices = np.argsort(dist_matrix[i])[:K+1]
        nearest_zones = [all_zones[j] for j in nearest_indices]
        accessible_jobs = sum(int(jobs_reindexed[z]) for z in nearest_zones)
        results[int(zone_id)] = {
            'total_jobs_in_zone': int(jobs_reindexed[zone_id]),
            'accessible_jobs_k10': int(accessible_jobs)
        }

    # Normalize to 0-100
    access_values = [r['accessible_jobs_k10'] for r in results.values()]
    min_val = min(access_values)
    max_val = max(access_values)
    range_val = max_val - min_val if max_val > min_val else 1

    for zone_id in results:
        score = (results[zone_id]['accessible_jobs_k10'] - min_val) / range_val * 100
        results[zone_id]['accessibility_score'] = round(score, 4)
        if score >= 67:
            results[zone_id]['accessibility_tier'] = 'High'
        elif score >= 33:
            results[zone_id]['accessibility_tier'] = 'Medium'
        else:
            results[zone_id]['accessibility_tier'] = 'Low'

    # Summary
    tiers = [r['accessibility_tier'] for r in results.values()]
    scores = [r['accessibility_score'] for r in results.values()]

    sorted_zones = sorted(results.items(), key=lambda x: x[1]['accessibility_score'])
    bottom_5 = [int(z[0]) for z in sorted_zones[:5]]

    ground_truth = {
        'total_zones': len(results),
        'total_jobs_mapped': total_jobs_mapped,
        'sum_jobs_in_zones': sum(r['total_jobs_in_zone'] for r in results.values()),
        'high_count': tiers.count('High'),
        'medium_count': tiers.count('Medium'),
        'low_count': tiers.count('Low'),
        'mean_score': round(float(np.mean(scores)), 4),
        'bottom_5_zones': bottom_5,
        'zones': results
    }

    with open('/tmp/ground_truth_accessibility.json', 'w') as f:
        json.dump(ground_truth, f, indent=2)
except Exception as e:
    with open('/tmp/ground_truth_accessibility.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

/opt/urbansim_env/bin/python /tmp/compute_ground_truth.py
chmod 600 /tmp/ground_truth_accessibility.json || true

# Ensure Jupyter Lab is running
if ! curl -s http://localhost:8888/api > /dev/null 2>&1; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && DISPLAY=:1 jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    # Wait for readiness
    for i in {1..30}; do
        if curl -s http://localhost:8888/api > /dev/null 2>&1; then
            break
        fi
        sleep 2
    done
fi

# Ensure Firefox is open and points to our notebook
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/employment_accessibility.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/employment_accessibility.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize Firefox
FIREFOX_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|Mozilla\|jupyter" | head -1 | awk '{print $1}')
if [ -n "$FIREFOX_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$FIREFOX_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$FIREFOX_WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="