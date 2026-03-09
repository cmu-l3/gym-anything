#!/bin/bash
set -e

echo "=== Setting up UrbanSim environment ==="

# Wait for desktop to be ready
sleep 5

# Activate virtualenv
source /opt/urbansim_env/bin/activate

# Create workspace directories
mkdir -p /home/ga/urbansim_projects
mkdir -p /home/ga/urbansim_projects/output
mkdir -p /home/ga/urbansim_projects/notebooks
mkdir -p /home/ga/urbansim_projects/data

# Copy data files to user workspace
cp /opt/urbansim_data/sanfran_public.h5 /home/ga/urbansim_projects/data/
cp /opt/urbansim_data/zones.json /home/ga/urbansim_projects/data/ 2>/dev/null || true

# Copy model configs and scripts
if [ -d /opt/urbansim_data/configs ]; then
    cp -r /opt/urbansim_data/configs /home/ga/urbansim_projects/
fi
cp /opt/urbansim_data/*.py /home/ga/urbansim_projects/ 2>/dev/null || true
cp /opt/urbansim_data/*.yaml /home/ga/urbansim_projects/ 2>/dev/null || true

# Create a welcome notebook
cat > /home/ga/urbansim_projects/notebooks/welcome.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Welcome to UrbanSim\n",
    "\n",
    "UrbanSim is a microsimulation platform for modeling urban development.\n",
    "\n",
    "## Available Data\n",
    "- **San Francisco parcel and building data** in `../data/sanfran_public.h5`\n",
    "- **Zone boundaries** in `../data/zones.json`\n",
    "\n",
    "## Getting Started\n",
    "Run the cells below to explore the data."
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
    "\n",
    "# Load the HDF5 data store\n",
    "store = pd.HDFStore('../data/sanfran_public.h5', mode='r')\n",
    "print('Available tables:')\n",
    "for key in store.keys():\n",
    "    df = store[key]\n",
    "    print(f'  {key}: {len(df)} rows x {len(df.columns)} columns')\n",
    "store.close()"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Quick look at buildings data\n",
    "buildings = pd.read_hdf('../data/sanfran_public.h5', 'buildings')\n",
    "print(f'Buildings: {len(buildings)} records')\n",
    "print(f'Columns: {list(buildings.columns)}')\n",
    "buildings.head()"
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

# Configure Jupyter Lab
mkdir -p /home/ga/.jupyter
cat > /home/ga/.jupyter/jupyter_lab_config.py << 'EOF'
c.ServerApp.open_browser = True
c.ServerApp.port = 8888
c.ServerApp.ip = '127.0.0.1'
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.root_dir = '/home/ga/urbansim_projects'
c.ServerApp.terminado_settings = {'shell_command': ['/bin/bash']}
EOF

# Set ownership
chown -R ga:ga /home/ga/urbansim_projects
chown -R ga:ga /home/ga/.jupyter

# Configure Firefox to suppress first-run dialogs
mkdir -p /home/ga/.mozilla/firefox/default-release

cat > /home/ga/.mozilla/firefox/default-release/user.js << 'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "http://localhost:8888");
user_pref("browser.newtabpage.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
EOF

cp /home/ga/.mozilla/firefox/default-release/user.js /home/ga/.mozilla/firefox/default-release/prefs.js

cat > /home/ga/.mozilla/firefox/profiles.ini << 'EOF'
[General]
StartWithLastProfile=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1
EOF

chown -R ga:ga /home/ga/.mozilla

# Start Jupyter Lab as ga user
echo "Starting Jupyter Lab..."
su - ga -c "source /opt/urbansim_env/bin/activate && cd /home/ga/urbansim_projects && DISPLAY=:1 jupyter lab --no-browser --port=8888 --ip=127.0.0.1 --NotebookApp.token='' --NotebookApp.password='' > /home/ga/.jupyter_lab.log 2>&1 &"

# Wait for Jupyter Lab to start
echo "Waiting for Jupyter Lab to start..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if curl -s http://localhost:8888/api > /dev/null 2>&1; then
        echo "Jupyter Lab is ready"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Jupyter Lab startup timeout. Checking logs..."
    cat /home/ga/.jupyter_lab.log 2>/dev/null | tail -20
fi

# Open Firefox pointing to Jupyter Lab
echo "Opening Firefox with Jupyter Lab..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8888' > /tmp/firefox.log 2>&1 &"

sleep 8

# Dismiss any Firefox dialogs
DISPLAY=:1 xdotool key Escape
sleep 1
DISPLAY=:1 xdotool key Escape

# Maximize Firefox window
FIREFOX_WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|Mozilla\|jupyter" | head -1 | awk '{print $1}')
if [ -n "$FIREFOX_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$FIREFOX_WID" -b add,maximized_vert,maximized_horz
    echo "Firefox window maximized"
fi

echo "=== UrbanSim setup complete ==="
echo "Jupyter Lab available at http://localhost:8888"
echo "Data: /home/ga/urbansim_projects/data/sanfran_public.h5"
