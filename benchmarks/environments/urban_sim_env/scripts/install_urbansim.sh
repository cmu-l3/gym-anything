#!/bin/bash
set -e

echo "=== Installing UrbanSim and dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install base dependencies
echo "Installing base dependencies..."
apt-get install -y \
    wget \
    curl \
    gnupg \
    ca-certificates \
    software-properties-common \
    build-essential \
    pkg-config \
    cmake

# Install GUI automation tools
echo "Installing GUI automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    scrot \
    imagemagick \
    python3-pip \
    python3-venv

# Install HDF5 development libraries (needed by PyTables/tables)
echo "Installing HDF5 libraries..."
apt-get install -y \
    libhdf5-dev \
    libhdf5-serial-dev \
    hdf5-tools

# Install Firefox for Jupyter Lab browser access
echo "Installing Firefox..."
apt-get install -y firefox

# Create a Python virtual environment for UrbanSim
echo "Creating Python virtual environment..."
python3 -m venv /opt/urbansim_env
source /opt/urbansim_env/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install UrbanSim and its ecosystem
echo "Installing UrbanSim packages..."
pip install \
    urbansim==3.2 \
    orca>=1.1 \
    pandana \
    urbansim_templates

# Install Jupyter Lab and visualization libraries
echo "Installing Jupyter Lab and data science libraries..."
pip install \
    jupyterlab \
    matplotlib \
    seaborn \
    geopandas \
    folium \
    plotly \
    nbformat \
    ipywidgets

# Install additional useful packages
pip install \
    scikit-learn \
    shapely \
    pyproj \
    ipykernel

# Register the Jupyter kernel for the UrbanSim venv
python -m ipykernel install --name urbansim --display-name "UrbanSim (Python 3)"

# Make the virtualenv accessible system-wide
echo "export PATH=/opt/urbansim_env/bin:\$PATH" >> /etc/profile.d/urbansim.sh
echo "export VIRTUAL_ENV=/opt/urbansim_env" >> /etc/profile.d/urbansim.sh
chmod +x /etc/profile.d/urbansim.sh

# Also set for ga user
echo "export PATH=/opt/urbansim_env/bin:\$PATH" >> /home/ga/.bashrc
echo "export VIRTUAL_ENV=/opt/urbansim_env" >> /home/ga/.bashrc

# Verify installations
echo "Verifying installations..."
python -c "import urbansim; print(f'UrbanSim version: {urbansim.__version__}')"
python -c "import orca; print('Orca imported successfully')"
python -c "import pandas; print(f'Pandas version: {pandas.__version__}')"
python -c "import numpy; print(f'NumPy version: {numpy.__version__}')"
python -c "import statsmodels; print(f'Statsmodels version: {statsmodels.__version__}')"
python -c "import matplotlib; print(f'Matplotlib version: {matplotlib.__version__}')"
jupyter lab --version

# Download the San Francisco UrbanSim data (real data)
echo "Downloading San Francisco UrbanSim dataset..."
mkdir -p /opt/urbansim_data
cd /opt/urbansim_data

# Download the official SF HDF5 dataset
wget -q -O sanfran_public.h5 \
    "https://github.com/UDST/sanfran_urbansim/raw/master/data/sanfran_public.h5" || {
    echo "WARNING: Could not download SF data from GitHub, trying alternative..."
    # Alternative: clone just the data
    apt-get install -y git-lfs 2>/dev/null || true
    git clone --depth 1 https://github.com/UDST/sanfran_urbansim.git /tmp/sanfran_urbansim 2>/dev/null || true
    if [ -f /tmp/sanfran_urbansim/data/sanfran_public.h5 ]; then
        cp /tmp/sanfran_urbansim/data/sanfran_public.h5 /opt/urbansim_data/
    fi
    rm -rf /tmp/sanfran_urbansim
}

# Download zone boundaries GeoJSON
wget -q -O zones.json \
    "https://github.com/UDST/sanfran_urbansim/raw/master/data/zones.json" || true

# Download the sanfran_urbansim model configs and notebooks
echo "Downloading model configuration files..."
git clone --depth 1 https://github.com/UDST/sanfran_urbansim.git /tmp/sanfran_repo 2>/dev/null || true
if [ -d /tmp/sanfran_repo ]; then
    cp -r /tmp/sanfran_repo/configs /opt/urbansim_data/ 2>/dev/null || true
    cp /tmp/sanfran_repo/*.py /opt/urbansim_data/ 2>/dev/null || true
    cp /tmp/sanfran_repo/*.ipynb /opt/urbansim_data/ 2>/dev/null || true
    cp /tmp/sanfran_repo/*.yaml /opt/urbansim_data/ 2>/dev/null || true
    rm -rf /tmp/sanfran_repo
fi

# Verify data
if [ -f /opt/urbansim_data/sanfran_public.h5 ]; then
    DATA_SIZE=$(du -sh /opt/urbansim_data/sanfran_public.h5 | cut -f1)
    echo "San Francisco dataset downloaded: $DATA_SIZE"
    python -c "
import pandas as pd
store = pd.HDFStore('/opt/urbansim_data/sanfran_public.h5', mode='r')
print('HDF5 tables:')
for key in store.keys():
    df = store[key]
    print(f'  {key}: {len(df)} rows, {len(df.columns)} columns')
store.close()
"
else
    echo "ERROR: Failed to download San Francisco dataset"
    exit 1
fi

# Set permissions
chown -R ga:ga /opt/urbansim_data
chmod -R 755 /opt/urbansim_data

deactivate

echo "=== UrbanSim installation complete ==="
