#!/bin/bash
echo "=== Setting up redevelopment_probability_upzoning task ==="

source /workspace/scripts/task_utils.sh

# ── CLEAN ──────────────────────────────────────────────────────────────────
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output
rm -f /home/ga/urbansim_projects/output/zone_development_impact.csv
rm -f /home/ga/urbansim_projects/output/model_metrics.json
rm -f /home/ga/urbansim_projects/output/scenario_comparison_chart.png
rm -f /home/ga/urbansim_projects/notebooks/redevelopment_model.ipynb
rm -f /tmp/redev_upzoning_result.json
rm -f /tmp/redev_upzoning_gt.json

# Verify cleanup succeeded before recording baseline
[ ! -f /home/ga/urbansim_projects/output/zone_development_impact.csv ] || { echo "ERROR: cleanup failed"; exit 1; }

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

buildings = pd.read_hdf(data_path, 'buildings')
households = pd.read_hdf(data_path, 'households')
parcels = pd.read_hdf(data_path, 'parcels')
zoning_for_parcels = pd.read_hdf(data_path, 'zoning_for_parcels')
zoning = pd.read_hdf(data_path, 'zoning')

# Count residential buildings
res_buildings = buildings[buildings['residential_units'] >= 1]
n_residential = int(len(res_buildings))

# Count buildings with valid building_sqft
n_valid_sqft = int(res_buildings['building_sqft'].notna().sum())

# Count recently developed
n_recently_developed = int((res_buildings['year_built'] >= 2000).sum())

# Zoning bridge table info
zfp_cols = list(zoning_for_parcels.columns)
zfp_index_name = zoning_for_parcels.index.name
n_zfp_rows = int(len(zoning_for_parcels))

# Count parcels with zoning data and max_far > 0
if len(zfp_cols) == 1:
    zoning_col = zfp_cols[0]
    parcels_with_zoning = zoning_for_parcels.join(
        zoning[['max_far']], on=zoning_col, how='left'
    )
    n_parcels_with_max_far_gt0 = int((parcels_with_zoning['max_far'] > 0).sum())
else:
    zoning_col = 'unknown'
    n_parcels_with_max_far_gt0 = 0

# Zone count from parcels
n_zones = int(parcels['zone_id'].nunique())

# Income stats for household join
income_median = float(households['income'].median())

gt = {
    'n_residential_buildings': n_residential,
    'n_valid_sqft': n_valid_sqft,
    'n_recently_developed': n_recently_developed,
    'n_zfp_rows': n_zfp_rows,
    'zfp_column': zoning_col,
    'zfp_index_name': str(zfp_index_name),
    'n_parcels_with_max_far_gt0': n_parcels_with_max_far_gt0,
    'n_zones': n_zones,
    'income_median': income_median,
    'total_buildings': int(len(buildings)),
    'total_households': int(len(households)),
    'total_parcels': int(len(parcels))
}

with open('/tmp/redev_upzoning_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"GT: n_residential={n_residential}, n_valid_sqft={n_valid_sqft}, "
      f"n_recently_developed={n_recently_developed}, "
      f"zfp_col={zoning_col}, zfp_index={zfp_index_name}, "
      f"parcels_with_max_far_gt0={n_parcels_with_max_far_gt0}, "
      f"n_zones={n_zones}")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

# ── SEED ──────────────────────────────────────────────────────────────────
# Record task start timestamp AFTER cleanup and GT computation
date +%s > /tmp/redev_upzoning_start_ts

# ── NOTEBOOK ──────────────────────────────────────────────────────────────
cat > /home/ga/urbansim_projects/notebooks/redevelopment_model.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Residential Redevelopment Probability Model with Upzoning Scenario\n",
    "\n",
    "Build a logistic regression model predicting which residential buildings are likely to be redeveloped,\n",
    "then project development impacts under a 50% upzoning scenario.\n",
    "\n",
    "**Data**: `/home/ga/urbansim_projects/data/sanfran_public.h5`\n",
    "\n",
    "**Required outputs**:\n",
    "- `/home/ga/urbansim_projects/output/model_metrics.json` — `auc_score`, `n_train`, `n_test`, `coefficients` (dict), `intercept`\n",
    "- `/home/ga/urbansim_projects/output/zone_development_impact.csv` — `zone_id`, `n_buildings`, `expected_baseline_developments`, `expected_scenario_developments`, `development_uplift`, `zone_median_income`\n",
    "- `/home/ga/urbansim_projects/output/scenario_comparison_chart.png` — scatter: baseline vs scenario expected developments, y=x line, colored by uplift"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/redevelopment_model.ipynb

# ── LAUNCH ────────────────────────────────────────────────────────────────
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/redevelopment_model.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/redevelopment_model.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/redev_upzoning_start.png

echo "GT: $(cat /tmp/redev_upzoning_gt.json)"
echo "=== Setup complete ==="
