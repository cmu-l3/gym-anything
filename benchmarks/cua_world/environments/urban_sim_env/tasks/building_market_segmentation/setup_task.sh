#!/bin/bash
echo "=== Setting up building_market_segmentation task ==="

source /workspace/scripts/task_utils.sh

# ── CLEAN ──────────────────────────────────────────────────────────────────
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output
rm -f /home/ga/urbansim_projects/output/building_clusters.csv
rm -f /home/ga/urbansim_projects/output/cluster_profiles.csv
rm -f /home/ga/urbansim_projects/output/market_segmentation_chart.png
rm -f /home/ga/urbansim_projects/notebooks/market_segmentation.ipynb
rm -f /tmp/building_segmentation_result.json
rm -f /tmp/building_segmentation_gt.json

[ ! -f /home/ga/urbansim_projects/output/building_clusters.csv ] || { echo "ERROR: cleanup failed"; exit 1; }

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
buildings = pd.read_hdf(data_path, 'buildings')

# Count buildings eligible for clustering (residential with valid price and sqft)
eligible = buildings[
    (buildings['residential_units'] > 0) &
    (buildings['building_sqft'] > 0) &
    (buildings['residential_sales_price'] > 0)
].copy()

eligible['price_per_sqft'] = eligible['residential_sales_price'] / eligible['building_sqft']

# Remove extreme outliers for reference
p5  = float(eligible['price_per_sqft'].quantile(0.05))
p95 = float(eligible['price_per_sqft'].quantile(0.95))
ref = eligible[(eligible['price_per_sqft'] >= p5) & (eligible['price_per_sqft'] <= p95)]

gt = {
    'eligible_building_count': int(len(eligible)),
    'price_per_sqft_p25': float(eligible['price_per_sqft'].quantile(0.25)),
    'price_per_sqft_p50': float(eligible['price_per_sqft'].quantile(0.50)),
    'price_per_sqft_p75': float(eligible['price_per_sqft'].quantile(0.75)),
    'price_per_sqft_min_ref': p5,
    'price_per_sqft_max_ref': p95,
    'year_built_min': int(buildings['year_built'].min()),
    'year_built_max': int(buildings['year_built'].max()),
    'total_buildings': int(len(buildings))
}

with open('/tmp/building_segmentation_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"GT: eligible={gt['eligible_building_count']}, "
      f"price_p50={gt['price_per_sqft_p50']:.2f}, "
      f"total={gt['total_buildings']}")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: GT computation failed"
    exit 1
fi

# ── SEED ──────────────────────────────────────────────────────────────────
date +%s > /tmp/building_segmentation_start_ts

cat > /home/ga/urbansim_projects/notebooks/market_segmentation.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# SF Building Market Segmentation\n",
    "\n",
    "Perform unsupervised market segmentation of San Francisco's residential building stock.\n",
    "\n",
    "**Data**: `/home/ga/urbansim_projects/data/sanfran_public.h5`\n",
    "\n",
    "**Required outputs**:\n",
    "- `/home/ga/urbansim_projects/output/building_clusters.csv` — columns: `building_id`, `cluster_id`, `price_per_sqft`\n",
    "- `/home/ga/urbansim_projects/output/cluster_profiles.csv` — 3 rows, columns: `cluster_id`, `mean_price_per_sqft`, `mean_age_years`, `mean_stories`, `mean_units`, `building_count`\n",
    "- `/home/ga/urbansim_projects/output/market_segmentation_chart.png` — scatter: price_per_sqft vs age, colored by cluster"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/market_segmentation.ipynb

# ── LAUNCH ────────────────────────────────────────────────────────────────
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/market_segmentation.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/market_segmentation.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/building_segmentation_start.png
echo "GT: $(cat /tmp/building_segmentation_gt.json)"
echo "=== Setup complete ==="
