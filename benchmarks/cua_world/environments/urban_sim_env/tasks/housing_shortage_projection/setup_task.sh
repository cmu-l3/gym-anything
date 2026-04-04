#!/bin/bash
echo "=== Setting up housing_shortage_projection task ==="

source /workspace/scripts/task_utils.sh

# ── CLEAN ──────────────────────────────────────────────────────────────────
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output
rm -f /home/ga/urbansim_projects/output/housing_shortage.csv
rm -f /home/ga/urbansim_projects/output/shortage_trend.png
rm -f /home/ga/urbansim_projects/notebooks/housing_shortage.ipynb
rm -f /tmp/housing_shortage_result.json
rm -f /tmp/housing_shortage_gt.json

[ ! -f /home/ga/urbansim_projects/output/housing_shortage.csv ] || { echo "ERROR: cleanup failed"; exit 1; }

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

# Check if zoning_for_parcels exists (needed for FAR computation)
import tables
with tables.open_file(data_path, 'r') as h:
    tables_in_file = [node._v_name for node in h.root]

try:
    zoning = pd.read_hdf(data_path, 'zoning')
    has_zoning = True
except Exception:
    has_zoning = False

total_households = len(households)
total_buildings = len(buildings)
total_parcels = len(parcels)

# Compute a reference feasibility count: parcels with some unused capacity
# This gives the agent reference values to sanity-check their simulation
residential_buildings = buildings[buildings['residential_units'] > 0]
avg_residential_density = float(
    residential_buildings['residential_units'].sum() / len(residential_buildings)
) if len(residential_buildings) > 0 else 5.0

gt = {
    'total_households_2020': total_households,
    'total_buildings': total_buildings,
    'total_parcels': total_parcels,
    'avg_residential_density_per_building': avg_residential_density,
    'has_zoning_table': has_zoning,
    'simulation_years': [2020, 2021, 2022, 2023, 2024]
}

with open('/tmp/housing_shortage_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"GT: households={total_households}, buildings={total_buildings}, "
      f"avg_density={avg_residential_density:.2f}")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

# ── SEED ──────────────────────────────────────────────────────────────────
date +%s > /tmp/housing_shortage_start_ts

cat > /home/ga/urbansim_projects/notebooks/housing_shortage.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# 5-Year Housing Shortage Projection (2020–2024)\n",
    "\n",
    "Build and run a 5-year UrbanSim orca simulation projecting housing supply vs demand for San Francisco.\n",
    "\n",
    "**Data**: `/home/ga/urbansim_projects/data/sanfran_public.h5`\n",
    "\n",
    "**Framework**: `import orca` — use `@orca.step()` decorator and `orca.run()`\n",
    "\n",
    "**Required outputs**:\n",
    "- `/home/ga/urbansim_projects/output/housing_shortage.csv` — 5 rows, columns: `year`, `households_start`, `new_households`, `new_units`, `annual_deficit`, `cumulative_deficit`\n",
    "- `/home/ga/urbansim_projects/output/shortage_trend.png` — line chart of new_households vs new_units per year"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Your simulation here\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/housing_shortage.ipynb

# ── LAUNCH ────────────────────────────────────────────────────────────────
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/housing_shortage.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/housing_shortage.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/housing_shortage_start.png
echo "GT: $(cat /tmp/housing_shortage_gt.json)"
echo "=== Setup complete ==="
