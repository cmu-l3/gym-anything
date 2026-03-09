#!/bin/bash
echo "=== Setting up zone_job_accessibility_equity task ==="

source /workspace/scripts/task_utils.sh

# ── CLEAN ──────────────────────────────────────────────────────────────────
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output
rm -f /home/ga/urbansim_projects/output/zone_accessibility.csv
rm -f /home/ga/urbansim_projects/output/equity_gap_chart.png
rm -f /home/ga/urbansim_projects/notebooks/job_accessibility_equity.ipynb
rm -f /tmp/zone_equity_result.json
rm -f /tmp/zone_equity_gt.json

[ ! -f /home/ga/urbansim_projects/output/zone_accessibility.csv ] || { echo "ERROR: cleanup failed"; exit 1; }

# ── RECORD (GT-in-Setup) ──────────────────────────────────────────────────
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
/opt/urbansim_env/bin/python3 << 'PYEOF'
import pandas as pd
import numpy as np
import json

data_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'

buildings  = pd.read_hdf(data_path, 'buildings')
households = pd.read_hdf(data_path, 'households')
parcels    = pd.read_hdf(data_path, 'parcels')
jobs       = pd.read_hdf(data_path, 'jobs')

# Income 30th percentile (task-defined low-income threshold)
income_p30 = float(households['income'].quantile(0.30))

# Zone-level household count (ground truth reference)
bldg_with_zone = buildings.join(parcels[['zone_id']], on='parcel_id', how='left')
hh_with_zone = households.join(
    bldg_with_zone[['zone_id']], on='building_id', how='left'
).dropna(subset=['zone_id'])
hh_with_zone['zone_id'] = hh_with_zone['zone_id'].astype(int)

zone_hh = hh_with_zone.groupby('zone_id').agg(
    total_households=('income', 'count'),
    low_income_households=('income', lambda x: (x < income_p30).sum())
).reset_index()

# Zone-level job count (ground truth reference)
jobs_with_zone = jobs.join(
    bldg_with_zone[['zone_id']], on='building_id', how='left'
).dropna(subset=['zone_id'])
jobs_with_zone['zone_id'] = jobs_with_zone['zone_id'].astype(int)

zone_jobs = jobs_with_zone.groupby('zone_id').size().reset_index(name='total_jobs')

# Merge for reference
zone_stats = zone_hh.merge(zone_jobs, on='zone_id', how='left').fillna(0)
zones_with_data = int(len(zone_stats[zone_stats['total_households'] > 0]))

gt = {
    'income_p30': income_p30,
    'total_households': int(len(households)),
    'total_jobs': int(len(jobs)),
    'zones_with_households': zones_with_data,
    'zones_with_jobs': int(len(zone_jobs)),
    'total_zones': int(len(zone_stats)),
    'median_jobs_per_zone': float(zone_jobs['total_jobs'].median())
}

with open('/tmp/zone_equity_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"GT: income_p30={income_p30:.0f}, zones_with_hh={zones_with_data}, "
      f"total_jobs={gt['total_jobs']}")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

# ── SEED ──────────────────────────────────────────────────────────────────
date +%s > /tmp/zone_equity_start_ts

cat > /home/ga/urbansim_projects/notebooks/job_accessibility_equity.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Zone-Level Job Accessibility Equity Analysis\n",
    "\n",
    "Compute an Equity Gap Score for each SF zone based on low-income household concentration and job accessibility.\n",
    "\n",
    "**Data**: `/home/ga/urbansim_projects/data/sanfran_public.h5`\n",
    "\n",
    "**Tables to use**: `jobs`, `households`, `buildings`, `parcels`\n",
    "\n",
    "**Low-income threshold**: 30th percentile of all SF household income\n",
    "\n",
    "**Required outputs**:\n",
    "- `/home/ga/urbansim_projects/output/zone_accessibility.csv` — columns: `zone_id`, `total_jobs`, `total_households`, `low_income_households`, `low_income_share`, `jobs_per_household`, `equity_gap_score`\n",
    "- `/home/ga/urbansim_projects/output/equity_gap_chart.png` — horizontal bar chart of top-15 worst-equity zones"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/job_accessibility_equity.ipynb

# ── LAUNCH ────────────────────────────────────────────────────────────────
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/job_accessibility_equity.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/job_accessibility_equity.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/zone_equity_start.png
echo "GT: $(cat /tmp/zone_equity_gt.json)"
echo "=== Setup complete ==="
