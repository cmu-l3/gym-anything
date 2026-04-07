#!/bin/bash
echo "=== Setting up residential_overcrowding_assessment task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output
rm -f /home/ga/urbansim_projects/output/overcrowding_by_zone.csv
rm -f /home/ga/urbansim_projects/output/overcrowding_top20.png

# Ensure data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

# Compute Ground Truth dynamically based on the exact dataset
echo "Computing ground truth..."
activate_venv
python - << 'EOF'
import pandas as pd
import json

h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
households = pd.read_hdf(h5_path, 'households')
buildings = pd.read_hdf(h5_path, 'buildings')
parcels = pd.read_hdf(h5_path, 'parcels')

# Join households to buildings to get parcel_id
if 'parcel_id' not in households.columns:
    if 'parcel_id' in buildings.columns:
        hh = households.merge(buildings[['parcel_id']], left_on='building_id', right_index=True, how='left')
    else:
        hh = households.copy()
else:
    hh = households.copy()

# Join to parcels to get zone_id
if 'zone_id' not in hh.columns:
    if 'zone_id' in parcels.columns:
        hh = hh.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True, how='left')

hh = hh.dropna(subset=['zone_id']).copy()
hh['zone_id'] = hh['zone_id'].astype(int)

# Total persons per zone
zone_persons = hh.groupby('zone_id')['persons'].sum().rename('total_persons')

# Total residential units per zone
bldg = buildings.copy()
if 'zone_id' not in bldg.columns:
    bldg = bldg.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True, how='left')
bldg = bldg.dropna(subset=['zone_id']).copy()
bldg['zone_id'] = bldg['zone_id'].astype(int)

zone_units = bldg.groupby('zone_id')['residential_units'].sum().rename('total_residential_units')

zone_df = pd.DataFrame({'total_persons': zone_persons, 'total_residential_units': zone_units}).dropna()
zone_df = zone_df[zone_df['total_residential_units'] > 0].copy()
zone_df['persons_per_unit'] = zone_df['total_persons'] / zone_df['total_residential_units']

# Overcrowded buildings calculations
bldg_persons = hh.groupby('building_id')['persons'].sum().rename('bldg_total_persons')
bldg_full = bldg.merge(bldg_persons, left_index=True, right_index=True, how='left')
bldg_full['bldg_total_persons'] = bldg_full['bldg_total_persons'].fillna(0)

res_bldg = bldg_full[bldg_full['residential_units'] > 0].copy()
res_bldg['is_overcrowded'] = (res_bldg['bldg_total_persons'] > res_bldg['residential_units']).astype(int)

zone_overcrowded = res_bldg.groupby('zone_id').agg(
    n_res_buildings=('residential_units', 'count'),
    n_overcrowded=('is_overcrowded', 'sum')
)
zone_overcrowded['pct_overcrowded_buildings'] = (zone_overcrowded['n_overcrowded'] / zone_overcrowded['n_res_buildings']) * 100

zone_df = zone_df.join(zone_overcrowded[['pct_overcrowded_buildings']], how='left').fillna(0)

ppu_min = zone_df['persons_per_unit'].min()
ppu_max = zone_df['persons_per_unit'].max()
zone_df['overcrowding_risk_index'] = ((zone_df['persons_per_unit'] - ppu_min) / (ppu_max - ppu_min)) * 100
zone_df = zone_df.reset_index()

gt = {
    'num_zones': len(zone_df),
    'sample_zones': {}
}

# Take 20 random zones for robust sampling checks later
sample = zone_df.sample(min(20, len(zone_df)), random_state=42)
for _, row in sample.iterrows():
    gt['sample_zones'][str(int(row['zone_id']))] = {
        'persons_per_unit': float(row['persons_per_unit']),
        'pct_overcrowded_buildings': float(row['pct_overcrowded_buildings']),
        'overcrowding_risk_index': float(row['overcrowding_risk_index'])
    }

with open('/tmp/overcrowding_ground_truth.json', 'w') as f:
    json.dump(gt, f)
EOF
# Restrict read access to GT file
chmod 600 /tmp/overcrowding_ground_truth.json

# Seed the starter Notebook
cat > /home/ga/urbansim_projects/notebooks/overcrowding_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Residential Overcrowding Risk Assessment\n",
    "\n",
    "Identify zones with potential residential overcrowding to prioritize housing code enforcement and plan targeted affordable housing.\n",
    "\n",
    "## Requirements:\n",
    "- Load households, buildings, and parcels tables from `../data/sanfran_public.h5`\n",
    "- Join households -> buildings -> parcels to determine `zone_id` for each household\n",
    "- Compute `total_persons` and `total_residential_units` for each zone\n",
    "- Compute `persons_per_unit` (ratio) for each zone\n",
    "- Compute `pct_overcrowded_buildings` (percentage of residential buildings where total household members > residential units)\n",
    "- Compute `overcrowding_risk_index` (min-max normalization of persons_per_unit scaled to 0-100)\n",
    "- Save DataFrame to `../output/overcrowding_by_zone.csv`\n",
    "- Save horizontal bar chart (top 20 risk zones) to `../output/overcrowding_top20.png`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Write your code here\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/overcrowding_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Ensure Firefox is running and point to the Notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/overcrowding_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/overcrowding_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss popups, maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Snapshot starting state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="