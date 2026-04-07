#!/bin/bash
echo "=== Setting up sfh_underutilization_analysis task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

date +%s > /home/ga/.task_start_time

if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found"
    exit 1
fi

activate_venv
python -c "
import pandas as pd
hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Households: {len(hh)} rows')
print(f'Buildings: {len(bld)} rows')
print(f'Parcels: {len(parcels)} rows')
assert len(hh) > 100, 'Not enough household records'
assert len(bld) > 100, 'Not enough building records'
assert len(parcels) > 100, 'Not enough parcel records'
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/sfh_underutilization.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Single-Family Housing Underutilization Analysis\n",
    "\n",
    "Analyze where large single-family homes are occupied by small households.\n",
    "\n",
    "## Requirements:\n",
    "- Load `households`, `buildings`, and `parcels` from `../data/sanfran_public.h5`\n",
    "- Join buildings to parcels to get `zone_id`\n",
    "- Group `households` by `building_id` and sum the `persons` column to get total people per building\n",
    "- Merge with `buildings` and filter for: `residential_units == 1`, `building_sqft >= 2000`, and `persons >= 1` (occupied)\n",
    "- Classify these buildings as Underutilized if `persons <= 2`\n",
    "- Aggregate by `zone_id` to compute `underutilization_rate`\n",
    "- Filter to zones with `>= 20` large SFHs and rank top 20 descending by underutilization_rate\n",
    "- Save CSV to `../output/underutilized_zones.csv`\n",
    "- Save bar chart of rates to `../output/underutilization_plot.png`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Write your code here\n",
    "import pandas as pd\n",
    "import matplotlib.pyplot as plt\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/sfh_underutilization.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/sfh_underutilization.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/sfh_underutilization.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="