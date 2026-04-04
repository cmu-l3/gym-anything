#!/bin/bash
set -e

echo "=== Installing PsychoPy Environment ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
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
    cmake \
    pkg-config \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    python3-setuptools \
    python3-wheel

# Install GUI automation tools (needed for testing)
echo "Installing GUI automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    scrot \
    imagemagick

# Install Mesa/OpenGL software renderer (critical for PsychoPy in VNC)
echo "Installing OpenGL software renderer..."
apt-get install -y \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    mesa-utils \
    libglu1-mesa \
    libglu1-mesa-dev \
    libosmesa6 \
    mesa-common-dev \
    freeglut3 \
    freeglut3-dev \
    libglew-dev

# Install audio libraries (PsychoPy uses portaudio for sound)
echo "Installing audio libraries..."
apt-get install -y \
    libportaudio2 \
    portaudio19-dev \
    libsndfile1 \
    libsndfile1-dev \
    libasound2-dev \
    pulseaudio \
    libpulse-dev

# Install wxPython system dependencies
echo "Installing wxPython system dependencies..."
apt-get install -y \
    libgtk-3-0 \
    libgtk-3-dev \
    libwebkit2gtk-4.0-37 \
    libsdl2-2.0-0 \
    libsdl2-dev \
    libnotify4 \
    libnotify-dev \
    libsm6 \
    libxtst6 \
    libxxf86vm1 \
    libxxf86vm-dev

# Remove system numpy/scipy to avoid version conflicts with pip packages
apt-get remove -y python3-numpy python3-scipy python3-matplotlib python3-pil python3-pandas 2>/dev/null || true

# Upgrade pip
python3 -m pip install --upgrade pip setuptools wheel

# Install numpy and scipy via pip FIRST (compatible versions)
echo "Installing scientific stack via pip..."
pip3 install --break-system-packages \
    "numpy>=1.26" \
    "scipy>=1.11" \
    matplotlib \
    pandas \
    pillow || true

# Install wxPython from prebuilt wheel (Ubuntu 22.04 Jammy)
echo "Installing wxPython from prebuilt wheel..."
pip3 install --break-system-packages \
    -f https://extras.wxpython.org/wxPython4/extras/linux/gtk3/ubuntu-22.04/ \
    wxPython || {
    echo "Prebuilt wxPython wheel failed, trying pip install..."
    pip3 install --break-system-packages wxPython || {
        echo "WARNING: wxPython installation failed. PsychoPy Builder may not work."
    }
}

# Install PsychoPy
echo "Installing PsychoPy..."
pip3 install --break-system-packages psychopy || {
    echo "First psychopy install attempt failed, trying with --no-deps..."
    pip3 install --break-system-packages --no-deps psychopy
    pip3 install --break-system-packages \
        pyglet pillow "numpy>=1.26" "scipy>=1.11" matplotlib pandas \
        openpyxl xlrd lxml configobj pyyaml \
        sounddevice psutil requests moviepy \
        pyopengl pyopengl-accelerate || true
}

# Install additional useful packages
pip3 install --break-system-packages \
    sounddevice \
    python-bidi \
    arabic-reshaper || true

# Set environment variable for software OpenGL rendering
echo 'export LIBGL_ALWAYS_SOFTWARE=1' >> /etc/environment
echo 'export LIBGL_ALWAYS_SOFTWARE=1' >> /home/ga/.bashrc

# Verify installations
echo "Verifying installations..."
python3 -c "import wx; print('wxPython version:', wx.version())" || echo "WARNING: wxPython not importable"
python3 -c "import psychopy; print('PsychoPy version:', psychopy.__version__)" || echo "WARNING: PsychoPy not importable"
python3 -c "import numpy; print('NumPy version:', numpy.__version__)"
python3 -c "import scipy; print('SciPy version:', scipy.__version__)"

# Create user directories
mkdir -p /home/ga/.psychopy3
mkdir -p /home/ga/PsychoPyExperiments
mkdir -p /home/ga/PsychoPyExperiments/data
mkdir -p /home/ga/PsychoPyExperiments/conditions
mkdir -p /home/ga/PsychoPyExperiments/demos
chown -R ga:ga /home/ga/.psychopy3
chown -R ga:ga /home/ga/PsychoPyExperiments

echo "=== PsychoPy installation complete ==="
