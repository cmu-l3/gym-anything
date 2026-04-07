#!/bin/bash
set -e

echo "=== Installing GNU Octave ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install GNU Octave with GUI and dependencies
apt-get install -y \
    octave \
    octave-common \
    octave-doc \
    gnuplot \
    gnuplot-x11 \
    liboctave-dev \
    scrot \
    wmctrl \
    xdotool \
    x11-utils \
    imagemagick \
    python3-pip \
    curl \
    wget \
    fonts-dejavu

# Install additional Octave packages for signal processing and statistics
# These are commonly used Octave Forge packages
apt-get install -y \
    octave-signal \
    octave-statistics \
    octave-io \
    octave-image \
    octave-optim \
    octave-struct \
    octave-control || true

# Copy real-world datasets to user home
mkdir -p /home/ga/Documents/datasets
cp /workspace/data/iris.csv /home/ga/Documents/datasets/
cp /workspace/data/earthquakes_2024_jan.csv /home/ga/Documents/datasets/
cp /workspace/data/auto_mpg.csv /home/ga/Documents/datasets/
chown -R ga:ga /home/ga/Documents

# Create output directory for plots
mkdir -p /home/ga/plots
chown -R ga:ga /home/ga/plots

echo "=== GNU Octave installation complete ==="
