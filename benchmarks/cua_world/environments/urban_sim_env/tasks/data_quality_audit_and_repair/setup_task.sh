#!/bin/bash
echo "=== Setting up data_quality_audit_and_repair task ==="

source /workspace/scripts/task_utils.sh

# ── CLEAN ──────────────────────────────────────────────────────────────────
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output
rm -f /home/ga/urbansim_projects/output/quality_report.csv
rm -f /home/ga/urbansim_projects/output/buildings_repaired.csv
rm -f /home/ga/urbansim_projects/output/quality_audit_chart.png
rm -f /home/ga/urbansim_projects/notebooks/data_quality_audit.ipynb
# Remove any leftover error file from previous runs
rm -f /home/ga/urbansim_projects/data/buildings_with_errors.csv
rm -f /tmp/data_quality_result.json
rm -f /tmp/data_quality_gt.json

[ ! -f /home/ga/urbansim_projects/output/quality_report.csv ] || { echo "ERROR: cleanup failed"; exit 1; }
[ ! -f /home/ga/urbansim_projects/data/buildings_with_errors.csv ] || { echo "ERROR: cleanup of error file failed"; exit 1; }

# ── RECORD (GT-in-Setup + error injection) ─────────────────────────────────
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
/opt/urbansim_env/bin/python3 << 'PYEOF'
import pandas as pd
import numpy as np
import json

np.random.seed(42)
data_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
buildings = pd.read_hdf(data_path, 'buildings').copy()
buildings.index.name = 'building_id'
# Ensure index is in a column
buildings_df = buildings.reset_index()

# ── Inject Error Category 1: Physical impossibility
#    (stories > 15 but building_sqft < 3000 — tall but tiny footprint)
candidates_phy = buildings_df[
    (buildings_df['stories'] > 15) &
    (buildings_df['building_sqft'] >= 5000)
].index
n_inject_phy = min(55, len(candidates_phy))
inject_phy_idx = np.random.choice(candidates_phy, n_inject_phy, replace=False)
buildings_df.loc[inject_phy_idx, 'building_sqft'] = np.random.randint(500, 2500, n_inject_phy)

# ── Inject Error Category 2: Temporal impossibility
#    (year_built outside [1849, 2024] — SF was incorporated in 1850)
candidates_year = buildings_df[
    (buildings_df['year_built'] >= 1850) & (buildings_df['year_built'] <= 2023)
].index
n_inject_year = min(38, len(candidates_year))
inject_year_idx = np.random.choice(candidates_year, n_inject_year, replace=False)
future_years = np.random.choice([2050, 2075, 2099, 2030, 2045], n_inject_year)
buildings_df.loc[inject_year_idx, 'year_built'] = future_years

# ── Inject Error Category 3: Price anomaly on residential buildings
#    (residential_units > 0 but residential_sales_price = 0)
candidates_price = buildings_df[
    (buildings_df['residential_units'] > 0) &
    (buildings_df['residential_sales_price'] > 0)
].index
n_inject_price = min(110, len(candidates_price))
inject_price_idx = np.random.choice(candidates_price, n_inject_price, replace=False)
buildings_df.loc[inject_price_idx, 'residential_sales_price'] = 0.0

# ── Inject Error Category 4: Density impossibility
#    (residential_units > 800 in buildings with stories < 5)
candidates_density = buildings_df[
    (buildings_df['stories'] < 5) &
    (buildings_df['residential_units'] < 500)
].index
n_inject_density = min(28, len(candidates_density))
inject_density_idx = np.random.choice(candidates_density, n_inject_density, replace=False)
buildings_df.loc[inject_density_idx, 'residential_units'] = np.random.randint(850, 2500, n_inject_density)

# Save the error-injected CSV
buildings_df.to_csv('/home/ga/urbansim_projects/data/buildings_with_errors.csv', index=False)

gt = {
    'total_buildings': len(buildings_df),
    'n_physical_impossibility': int(n_inject_phy),
    'n_year_impossibility': int(n_inject_year),
    'n_price_anomaly': int(n_inject_price),
    'n_density_impossibility': int(n_inject_density),
    'total_injected_errors': int(n_inject_phy + n_inject_year + n_inject_price + n_inject_density),
    'error_categories': ['physical_impossibility', 'year_impossibility', 'price_anomaly', 'density_impossibility'],
    'columns': list(buildings_df.columns)
}
with open('/tmp/data_quality_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"Injected errors: phy={n_inject_phy}, year={n_inject_year}, price={n_inject_price}, density={n_inject_density}")
print(f"Total buildings: {len(buildings_df)}")
print(f"buildings_with_errors.csv created at /home/ga/urbansim_projects/data/")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: error injection failed"
    exit 1
fi

chown ga:ga /home/ga/urbansim_projects/data/buildings_with_errors.csv

# ── SEED ──────────────────────────────────────────────────────────────────
date +%s > /tmp/data_quality_start_ts

cat > /home/ga/urbansim_projects/notebooks/data_quality_audit.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Buildings Database Quality Audit and Repair\n",
    "\n",
    "Conduct a full data quality audit of the SF buildings dataset, identify all anomaly categories, repair them, and produce a QA report.\n",
    "\n",
    "**Input data**: `/home/ga/urbansim_projects/data/buildings_with_errors.csv`\n",
    "\n",
    "**Reference**: `/home/ga/urbansim_projects/data/sanfran_public.h5` (for valid value ranges)\n",
    "\n",
    "**Required outputs**:\n",
    "- `/home/ga/urbansim_projects/output/quality_report.csv` — columns: `issue_type`, `records_affected`, `repair_method`, `records_repaired`\n",
    "- `/home/ga/urbansim_projects/output/buildings_repaired.csv` — full repaired dataset\n",
    "- `/home/ga/urbansim_projects/output/quality_audit_chart.png` — bar chart of records_affected per issue_type"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Your audit here\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/data_quality_audit.ipynb

# ── LAUNCH ────────────────────────────────────────────────────────────────
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/data_quality_audit.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/data_quality_audit.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/data_quality_start.png
echo "GT: $(cat /tmp/data_quality_gt.json)"
echo "=== Setup complete ==="
