#!/bin/bash
set -e
echo "=== Setting up model_naca_airfoil task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Clean up previous artifacts
rm -f /home/ga/Documents/FreeCAD/wing_section.FCStd
rm -f /home/ga/Documents/FreeCAD/naca2412.dat

# ==============================================================================
# Generate NACA 2412 Data File
# We use Python to generate precise aerodynamic coordinates
# ==============================================================================
cat << 'PY_EOF' > /tmp/generate_naca.py
import numpy as np

def naca4(number, n_points=60, chord=100.0):
    m = int(number[0]) / 100.0
    p = int(number[1]) / 10.0
    t = int(number[2:]) / 100.0

    # X coordinates (cosine spacing for better leading edge resolution)
    beta = np.linspace(0, np.pi, n_points // 2 + 1)
    x = (0.5 * (1 - np.cos(beta))) 
    
    # Thickness distribution
    yt = 5 * t * (0.2969 * np.sqrt(x) - 0.1260 * x - 0.3516 * x**2 + 
                  0.2843 * x**3 - 0.1015 * x**4)

    # Camber line and gradient
    yc = np.zeros_like(x)
    dyc_dx = np.zeros_like(x)
    
    for i in range(len(x)):
        if x[i] <= p:
            yc[i] = (m / p**2) * (2 * p * x[i] - x[i]**2)
            dyc_dx[i] = (2 * m / p**2) * (p - x[i])
        else:
            yc[i] = (m / (1 - p)**2) * ((1 - 2 * p) + 2 * p * x[i] - x[i]**2)
            dyc_dx[i] = (2 * m / (1 - p)**2) * (p - x[i])

    theta = np.arctan(dyc_dx)

    # Upper surface
    xu = x - yt * np.sin(theta)
    yu = yc + yt * np.cos(theta)

    # Lower surface
    xl = x + yt * np.sin(theta)
    yl = yc - yt * np.cos(theta)

    # Combine (Upper surface back-to-front, then Lower surface front-to-back)
    X = np.concatenate((xu[::-1], xl[1:]))
    Y = np.concatenate((yu[::-1], yl[1:]))

    # Scale by chord
    return X * chord, Y * chord

x, y = naca4("2412", n_points=60, chord=100.0)

# Write to file (Selig format style: X Y)
with open("/home/ga/Documents/FreeCAD/naca2412.dat", "w") as f:
    for i in range(len(x)):
        f.write(f"{x[i]:.4f} {y[i]:.4f} 0.0000\n")
PY_EOF

python3 /tmp/generate_naca.py
chown ga:ga /home/ga/Documents/FreeCAD/naca2412.dat
rm -f /tmp/generate_naca.py

echo "Generated NACA 2412 data at /home/ga/Documents/FreeCAD/naca2412.dat"

# ==============================================================================
# Start FreeCAD
# ==============================================================================

# Kill any running instance
kill_freecad

# Launch FreeCAD
echo "Starting FreeCAD..."
launch_freecad

# Wait for window
wait_for_freecad 30

# Maximize
maximize_freecad

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="