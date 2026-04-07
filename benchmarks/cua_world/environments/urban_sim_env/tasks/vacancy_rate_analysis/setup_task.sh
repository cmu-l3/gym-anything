#!/bin/bash
echo "=== Setting up vacancy_rate_analysis task ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Create output directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Clear any previous outputs
rm -f /home/ga/urbansim_projects/output/vacancy_by_zone.csv
rm -f /home/ga/urbansim_projects/output/vacancy_summary.json
rm -f /home/ga/urbansim_projects/output/vacancy_distribution.png
rm -f /home/ga/urbansim_projects/notebooks/vacancy_analysis.ipynb

# Verify dataset
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found. Attempting to copy..."
    cp /opt/urbansim_data/sanfran_public.h5 /home/ga/urbansim_projects/data/ 2>/dev/null || exit 1
    chown ga:ga /home/ga/urbansim_projects/data/sanfran_public.h5
fi

# Pre-compute ground truth and store in hidden location
mkdir -p /var/lib/urbansim_ground_truth
chmod 700 /var/lib/urbansim_ground_truth

python - << 'PYEOF'
import pandas as pd
import json
import warnings
warnings.filterwarnings('ignore')

path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
try:
    b = pd.read_hdf(path, 'buildings')
    h = pd.read_hdf(path, 'households')
    p = pd.read_hdf(path, 'parcels')

    # Assign zone_id to buildings
    if 'zone_id' in p.columns:
        if 'parcel_id' in p.columns:
            p_map = p.set_index('parcel_id')['zone_id']
        else:
            p_map = p['zone_id']
    else:
        p_map = pd.Series(dtype=int)

    if 'parcel_id' in b.columns:
        b['zone_id'] = b['parcel_id'].map(p_map)
    else:
        b['zone_id'] = pd.Series(b.index).map(p_map)

    # Count households per building
    if 'building_id' in h.columns:
        hh_counts = h.groupby('building_id').size()
    else:
        hh_counts = h.groupby(h.index).size()

    b['occupied_units'] = pd.Series(b.index).map(hh_counts).fillna(0).values

    # Aggregate by zone
    zone_stats = b.groupby('zone_id').agg(
        total_units=('residential_units', 'sum'),
        occupied_units=('occupied_units', 'sum')
    ).reset_index()

    zone_stats = zone_stats[zone_stats['total_units'] > 0].copy()
    zone_stats['vacant_units'] = zone_stats['total_units'] - zone_stats['occupied_units']
    zone_stats['vacancy_rate'] = zone_stats['vacant_units'] / zone_stats['total_units']

    city_tot = float(zone_stats['total_units'].sum())
    city_vac = float(zone_stats['vacant_units'].sum())
    city_rate = city_vac / city_tot if city_tot > 0 else 0.0

    m = zone_stats[zone_stats['total_units'] >= 50]
    high_z = int(m.loc[m['vacancy_rate'].idxmax(), 'zone_id']) if not m.empty else -1
    low_z = int(m.loc[m['vacancy_rate'].idxmin(), 'zone_id']) if not m.empty else -1

    def classify(r):
        if r['total_units'] < 50: return 'insufficient_data'
        if r['vacancy_rate'] < 0.05: return 'tight'
        if r['vacancy_rate'] <= 0.10: return 'healthy'
        return 'soft'

    zone_stats['market_condition'] = zone_stats.apply(classify, axis=1)

    gt = {
        'citywide_vacancy_rate': city_rate,
        'num_zones_analyzed': len(zone_stats),
        'highest_vacancy_zone_id': high_z,
        'lowest_vacancy_zone_id': low_z,
        'num_tight_zones': int((zone_stats['market_condition'] == 'tight').sum()),
        'num_healthy_zones': int((zone_stats['market_condition'] == 'healthy').sum()),
        'num_soft_zones': int((zone_stats['market_condition'] == 'soft').sum())
    }

    with open('/var/lib/urbansim_ground_truth/vacancy_ground_truth.json', 'w') as f:
        json.dump(gt, f)
    print("Ground truth pre-computed successfully.")
except Exception as e:
    print(f"Error computing ground truth: {e}")
PYEOF

chmod 600 /var/lib/urbansim_ground_truth/vacancy_ground_truth.json 2>/dev/null || true

# Prepare starter notebook
cat > /home/ga/urbansim_projects/notebooks/vacancy_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Zone-Level Residential Vacancy Analysis\n",
    "\n",
    "Analyze housing vacancy rates to assess market tightness across San Francisco zones.\n",
    "\n",
    "## Objectives:\n",
    "- Load buildings, households, and parcels from `../data/sanfran_public.h5`\n",
    "- Compute vacancy rates at the zone level\n",
    "- Export results to CSV, JSON, and PNG as specified in the task description"
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
    "import json\n",
    "\n",
    "# Write your code here"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/vacancy_analysis.ipynb

# Start Jupyter Lab if needed
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Point Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/vacancy_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/vacancy_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Clean up screen and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="