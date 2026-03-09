#!/bin/bash
echo "=== Setting up run_simulation_year task ==="

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
store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
for key in store.keys():
    df = store[key]
    print(f'{key}: {len(df)} rows')
store.close()
print('Data verification passed')
"

cat > /home/ga/urbansim_projects/notebooks/simulation.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# UrbanSim Simulation: Year 2010\n",
    "\n",
    "Run a single-year urban development simulation using orca.\n",
    "\n",
    "## Requirements:\n",
    "- Load SF data from `../data/sanfran_public.h5`\n",
    "- Register tables with orca\n",
    "- Define at least 2 simulation steps\n",
    "- Run for year 2010\n",
    "- Save summary CSV to `../output/simulation_summary.csv`\n",
    "- Save comparison chart to `../output/simulation_comparison.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/simulation.ipynb

if ! is_jupyter_running; then
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/simulation.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/simulation.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
