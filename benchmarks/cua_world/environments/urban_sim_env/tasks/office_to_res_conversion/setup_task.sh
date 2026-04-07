#!/bin/bash
echo "=== Setting up office_to_res_conversion task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Create necessary directories
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects

# Check dataset
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found. Cannot proceed."
    exit 1
fi

# Verify data availability
activate_venv
python -c "
import pandas as pd
bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
print(f'Buildings: {len(bld)} rows. Parcels: {len(parcels)} rows.')
assert len(bld) > 1000, 'Insufficient buildings data'
"

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/office_conversion.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Office-to-Residential Conversion Viability\n",
    "\n",
    "Identify underperforming office buildings suitable for residential conversion.\n",
    "\n",
    "## Task Checklist:\n",
    "- [ ] Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- [ ] Join on `parcel_id` to get `zone_id`\n",
    "- [ ] Filter: `building_type_id == 4`, `1800 < year_built < 1990`, `non_residential_sqft >= 50000`, `residential_units` is 0/NaN, `residential_sales_price > 0`\n",
    "- [ ] Engineer: `building_age = 2026 - year_built`, `value_per_sqft`, `potential_new_units = floor(non_residential_sqft / 1000)`\n",
    "- [ ] Score: `viability_score = (0.6 * value_score) + (0.4 * age_score)` using min-max scaling (invert value_score so cheaper=higher)\n",
    "- [ ] Output 1: Top 50 CSV to `../output/top_conversion_candidates.csv`\n",
    "- [ ] Output 2: Zone capacity CSV to `../output/zone_conversion_capacity.csv`\n",
    "- [ ] Output 3: Scatter plot PNG to `../output/conversion_scatter.png`"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Start your analysis here\n",
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
chown ga:ga /home/ga/urbansim_projects/notebooks/office_conversion.ipynb

# Ensure Jupyter is running
if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Notebook in Firefox
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/office_conversion.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/office_conversion.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Reset focus, dismiss popups, and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="