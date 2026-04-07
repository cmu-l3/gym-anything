#!/bin/bash
echo "=== Setting up historic_preservation_analysis task ==="

source /workspace/scripts/task_utils.sh

# Create required output directory
mkdir -p /home/ga/urbansim_projects/output
chown ga:ga /home/ga/urbansim_projects/output

# Timestamp for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Verify real HDF5 dataset exists
if [ ! -f /home/ga/urbansim_projects/data/sanfran_public.h5 ]; then
    echo "ERROR: SF data not found at /home/ga/urbansim_projects/data/sanfran_public.h5"
    exit 1
fi

activate_venv

# Create a starter Jupyter Notebook
cat > /home/ga/urbansim_projects/notebooks/historic_analysis.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Historic Residential Character and Value Analysis\n",
    "\n",
    "Identify zones with high concentrations of historic buildings and high market valuations.\n",
    "\n",
    "## Requirements:\n",
    "- Load `buildings` and `parcels` from `../data/sanfran_public.h5`\n",
    "- Filter for valid residential properties: `residential_sales_price > 0` and `year_built > 1800`\n",
    "- Categorize: Historic (`year_built < 1940`) vs Modern (`year_built >= 1940`)\n",
    "- Aggregate to `zone_id` computing counts, percentage, and average prices\n",
    "- Filter for statistically significant zones (`total_buildings >= 50` and `historic_count >= 10`)\n",
    "- Sort by `avg_historic_price` descending\n",
    "- Save CSV to `../output/historic_zones.csv`\n",
    "- Save scatter plot to `../output/historic_scatter.png`"
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
chown ga:ga /home/ga/urbansim_projects/notebooks/historic_analysis.ipynb

# Ensure Jupyter Lab is running
if ! is_jupyter_running; then
    echo "Starting Jupyter Lab..."
    su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"
    wait_for_jupyter 60
fi

# Point Firefox to the created notebook
if ! is_firefox_running; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888/lab/tree/notebooks/historic_analysis.ipynb' > /tmp/firefox.log 2>&1 &"
    sleep 8
else
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost:8888/lab/tree/notebooks/historic_analysis.ipynb"
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Maximize Window and clear dialogs
DISPLAY=:1 xdotool key Escape
sleep 1
maximize_firefox
sleep 2

# Initial evidence screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="