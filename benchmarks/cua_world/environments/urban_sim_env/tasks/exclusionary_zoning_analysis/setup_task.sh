#!/bin/bash
echo "=== Setting up exclusionary_zoning_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create output and notebooks directories if they don't exist
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
chown -R ga:ga /home/ga/urbansim_projects/output
chown -R ga:ga /home/ga/urbansim_projects/notebooks

# Clean any existing output from previous runs
rm -f /home/ga/urbansim_projects/output/exclusionary_zoning_metrics.csv
rm -f /home/ga/urbansim_projects/output/zoning_equity_summary.json
rm -f /home/ga/urbansim_projects/output/sf_income_scatter.png

# Record task start time for anti-gaming verification
date +%s > /home/ga/.task_start_time
echo "Task start time recorded: $(cat /home/ga/.task_start_time)"

# Verify data exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF dataset not found at expected location."
    exit 1
fi

activate_venv
python -c "
import pandas as pd
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
required_tables = ['buildings', 'parcels', 'households']
for tbl in required_tables:
    assert tbl in store, f'Missing {tbl} table'
store.close()
print('Data verification passed')
"

# Create starter notebook
cat > /home/ga/urbansim_projects/notebooks/exclusionary_zoning.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Exclusionary Zoning & Single-Family Dominance Analysis\n",
    "\n",
    "Analyze the relationship between single-family zoning dominance and household income.\n",
    "\n",
    "## Task Checklist:\n",
    "- [ ] Load `buildings`, `parcels`, and `households` from `../data/sanfran_public.h5`\n",
    "- [ ] Deduce the single-family `building_type_id` (usually where `residential_units == 1`)\n",
    "- [ ] Calculate zone-level `total_res_units`, `sf_units`, and `sf_pct`\n",
    "- [ ] Calculate zone-level `median_income` by joining households\n",
    "- [ ] Filter out zones with `< 50` total units or missing income\n",
    "- [ ] Categorize into `Exclusive SF` (sf_pct > 0.80) and `Diverse` (sf_pct <= 0.80)\n",
    "- [ ] Export zone metrics to `../output/exclusionary_zoning_metrics.csv`\n",
    "- [ ] Export aggregate JSON to `../output/zoning_equity_summary.json`\n",
    "- [ ] Export scatter plot to `../output/sf_income_scatter.png`"
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
    "# Your analysis here...\n"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/exclusionary_zoning.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Open Firefox to the notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/exclusionary_zoning.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to the notebook
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/exclusionary_zoning.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Dismiss any dialogs and maximize
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Take initial screenshot after browser is ready
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="