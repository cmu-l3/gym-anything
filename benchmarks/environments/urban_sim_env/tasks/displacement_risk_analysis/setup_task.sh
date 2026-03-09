#!/bin/bash
echo "=== Setting up displacement_risk_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── CLEAN ──────────────────────────────────────────────────────────────────
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output
rm -f /home/ga/urbansim_projects/output/displacement_risk.csv
rm -f /home/ga/urbansim_projects/output/displacement_risk_chart.png
rm -f /home/ga/urbansim_projects/notebooks/displacement_risk.ipynb
rm -f /tmp/displacement_risk_result.json
rm -f /tmp/displacement_risk_gt.json

# Verify cleanup succeeded before recording baseline
[ ! -f /home/ga/urbansim_projects/output/displacement_risk.csv ] || { echo "ERROR: cleanup failed"; exit 1; }

# ── RECORD (GT-in-Setup) ──────────────────────────────────────────────────
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
/opt/urbansim_env/bin/python3 << 'PYEOF'
import pandas as pd
import json

data_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'

buildings  = pd.read_hdf(data_path, 'buildings')
households = pd.read_hdf(data_path, 'households')
parcels    = pd.read_hdf(data_path, 'parcels')

# Compute income 25th percentile (definition of "low-income" for this task)
income_p25 = float(households['income'].quantile(0.25))

# Compute zone-level household counts
bldg_zone = buildings[['residential_units']].copy()
bldg_zone.index.name = 'building_id'
# buildings index = building_id; parcels has parcel_id (index) + zone_id
bldg_parcels = buildings.join(parcels[['zone_id']], on='parcel_id', how='left')
households_with_zone = households.join(
    bldg_parcels[['zone_id']], on='building_id', how='left'
).dropna(subset=['zone_id'])
households_with_zone['zone_id'] = households_with_zone['zone_id'].astype(int)

zone_hh = households_with_zone.groupby('zone_id').agg(
    total_households=('income', 'count'),
    low_income_households=('income', lambda x: (x < income_p25).sum())
).reset_index()

# Count zones with at least 10 households (meaningful data)
zones_with_data = int((zone_hh['total_households'] >= 10).sum())
total_zones = int(len(zone_hh))

gt = {
    'income_p25': income_p25,
    'zones_with_data': zones_with_data,
    'total_zones': total_zones,
    'total_households': int(len(households)),
    'total_buildings': int(len(buildings))
}

with open('/tmp/displacement_risk_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"GT computed: income_p25={income_p25:.0f}, zones_with_data={zones_with_data}, total_zones={total_zones}")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

# ── SEED ──────────────────────────────────────────────────────────────────
# Record task start timestamp AFTER cleanup and GT computation
date +%s > /tmp/displacement_risk_start_ts

# Create blank starter notebook
cat > /home/ga/urbansim_projects/notebooks/displacement_risk.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# San Francisco Displacement Risk Index\n",
    "\n",
    "Build a zone-level Displacement Risk Index (DRI) for San Francisco to guide anti-displacement investment.\n",
    "\n",
    "**Data**: `/home/ga/urbansim_projects/data/sanfran_public.h5`\n",
    "\n",
    "**Required outputs**:\n",
    "- `/home/ga/urbansim_projects/output/displacement_risk.csv` — columns: `zone_id`, `dri_score`, `vulnerability_score`, `precarity_score`, `pressure_score`, `low_income_households`, `total_households`, `mean_price_per_sqft`\n",
    "- `/home/ga/urbansim_projects/output/displacement_risk_chart.png` — top-20 zones by DRI, horizontal bar chart"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Your analysis here\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/displacement_risk.ipynb

# ── LAUNCH ────────────────────────────────────────────────────────────────
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/displacement_risk.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/displacement_risk.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/displacement_risk_start.png

echo "GT: $(cat /tmp/displacement_risk_gt.json)"
echo "=== Setup complete ==="
