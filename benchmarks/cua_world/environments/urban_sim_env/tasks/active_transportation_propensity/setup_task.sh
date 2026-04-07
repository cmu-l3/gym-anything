#!/bin/bash
echo "=== Setting up active_transportation_propensity task ==="

source /workspace/scripts/task_utils.sh

# Create output and notebook directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Record task start time
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv

# Pre-compute ground truth to prevent tampering, store in /tmp
# We execute a safe python script that generates top 5 zones and saves to JSON
cat > /tmp/generate_gt.py << 'EOF'
import pandas as pd
import json
import traceback

try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    parcels = store['parcels']
    buildings = store['buildings']
    households = store['households']
    jobs = store['jobs']
    store.close()

    # Create mapping of building_id to zone_id
    if 'zone_id' in parcels.columns:
        b_zone = buildings[['parcel_id']].merge(parcels[['zone_id']], left_on='parcel_id', right_index=True)
    else:
        # Fallback if index mapping is different
        b_zone = buildings.copy()
        b_zone['zone_id'] = 1 # Dummy fallback

    h_zone = households.merge(b_zone[['zone_id']], left_on='building_id', right_index=True)
    j_zone = jobs.merge(b_zone[['zone_id']], left_on='building_id', right_index=True)

    # Aggregate
    zone_parcels = parcels.groupby('zone_id').size().rename('parcel_count')
    zone_hh = h_zone.groupby('zone_id').size().rename('total_households')
    zero_car = h_zone[h_zone['cars'] == 0].groupby('zone_id').size().rename('zero_car_households')
    zone_jobs = j_zone.groupby('zone_id').size().rename('total_jobs')

    df = pd.concat([zone_parcels, zone_hh, zero_car, zone_jobs], axis=1).fillna(0)
    df = df[(df['parcel_count'] >= 50) & (df['total_households'] > 0)]

    df['hh_density'] = df['total_households'] / df['parcel_count']
    df['job_density'] = df['total_jobs'] / df['parcel_count']
    df['zero_car_pct'] = df['zero_car_households'] / df['total_households']

    for c in ['hh_density', 'job_density', 'zero_car_pct']:
        c_min = df[c].min()
        c_max = df[c].max()
        if c_max > c_min:
            df[f'{c}_norm'] = (df[c] - c_min) / (c_max - c_min)
        else:
            df[f'{c}_norm'] = 0.0

    df['atp_score'] = (df['hh_density_norm'] + df['job_density_norm'] + df['zero_car_pct_norm']) / 3
    df = df.sort_values('atp_score', ascending=False)
    
    top_5 = df.head(5).index.astype(int).tolist()
    with open('/tmp/ground_truth_top5.json', 'w') as f:
        json.dump(top_5, f)
except Exception as e:
    print(f"GT generation failed: {e}")
    traceback.print_exc()
    with open('/tmp/ground_truth_top5.json', 'w') as f:
        json.dump([], f)
EOF
python /tmp/generate_gt.py
rm /tmp/generate_gt.py

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/active_transportation_index.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Active Transportation Propensity Index\n",
    "\n",
    "Compute a composite index identifying optimal neighborhoods for micro-mobility investments.\n",
    "\n",
    "## Requirements:\n",
    "- Load `parcels`, `buildings`, `households`, and `jobs` from `../data/sanfran_public.h5`\n",
    "- Establish `zone_id` for every household and job\n",
    "- Aggregate base metrics per zone: `parcel_count`, `total_households`, `total_jobs`, `zero_car_households`\n",
    "- Filter out zones where `parcel_count < 50` or `total_households == 0`\n",
    "- Compute `hh_density`, `job_density`, and `zero_car_pct`\n",
    "- Min-Max normalize these 3 components (0.0 - 1.0 scale based on the filtered data max/min)\n",
    "- Calculate `atp_score` as the average of the 3 normalized components\n",
    "- Export top-ranked CSV to `../output/active_transit_scores.csv`\n",
    "- Export visualization to `../output/top_atps_zones.png`"
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
    "# Start your analysis here\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/active_transportation_index.ipynb

# Record initial state
echo '{"notebook_exists": true, "csv_exists": false, "plot_exists": false}' > /tmp/initial_state.json

# Start Jupyter Lab
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/active_transportation_index.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/active_transportation_index.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss dialogs and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot after browser is ready
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="