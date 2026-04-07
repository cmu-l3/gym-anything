#!/bin/bash
# Setup script for openvsp_stl_reverse_engineering task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_stl_reverse_engineering ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Generate a high-resolution binary STL of a swept, dihedral NACA wing
# We generate it physically in Python to ensure it uses real aerodynamic profiles
# rather than being a trivial box, making the mesh realistic.
python3 << 'PYEOF'
import struct, math, sys

SPAN = 10.0
ROOT = 2.0
TIP = 1.0
SWEEP = 5.0
DIHEDRAL = 3.0
OUTPUT_PATH = '/home/ga/Desktop/scanned_uav_wing.stl'

def naca(x):
    t = 0.12; m = 0.02; p = 0.4
    yc = (m/p**2)*(2*p*x - x**2) if x < p else (m/(1-p)**2)*((1-2*p) + 2*p*x - x**2)
    dyc = (2*m/p**2)*(p - x) if x < p else (2*m/(1-p)**2)*(p - x)
    yt = 5*t*(0.2969*math.sqrt(x) - 0.1260*x - 0.3516*x**2 + 0.2843*x**3 - 0.1015*x**4)
    th = math.atan(dyc)
    return (x - yt*math.sin(th), yc + yt*math.cos(th)), (x + yt*math.sin(th), yc - yt*math.cos(th))

def airfoil(chord, num=20):
    pts = []
    for i in range(num+1):
        x = 0.5*(1-math.cos(math.pi*i/num))
        u, l = naca(x)
        pts.append((u[0]*chord, u[1]*chord))
    for i in range(num-1, 0, -1):
        x = 0.5*(1-math.cos(math.pi*i/num))
        u, l = naca(x)
        pts.append((l[0]*chord, l[1]*chord))
    return pts

def get_3d(y_pos, chord, dx, dz):
    return [(x + dx, y_pos, z + dz) for x, z in airfoil(chord)]

sections = []
y_steps = 15
for i in range(y_steps + 1):
    f = i / y_steps
    y = f * (SPAN / 2)
    c = ROOT * (1 - f) + TIP * f
    dx = y * math.tan(math.radians(SWEEP))
    dz = y * math.tan(math.radians(DIHEDRAL))
    sections.append((y, get_3d(y, c, dx, dz)))
    if y > 0:
        sections.append((-y, get_3d(-y, c, dx, dz)))

# Sort by Y ascending
sections.sort(key=lambda item: item[0])
sec_points = [item[1] for item in sections]

tris = []
for i in range(len(sec_points) - 1):
    s1 = sec_points[i]
    s2 = sec_points[i+1]
    for j in range(len(s1)):
        j_next = (j + 1) % len(s1)
        tris.append((s1[j], s2[j], s1[j_next]))
        tris.append((s1[j_next], s2[j], s2[j_next]))

# Write Binary STL
with open(OUTPUT_PATH, 'wb') as f:
    f.write(b'OpenVSP_Task_Generated_STL' + b' ' * 54)
    f.write(struct.pack('<I', len(tris)))
    for t in tris:
        f.write(struct.pack('<3f', 0,0,0)) # Normal
        for p in t:
            f.write(struct.pack('<3f', p[0], p[1], p[2]))
        f.write(struct.pack('<H', 0))

print(f"Generated realistic mesh with {len(tris)} triangles at {OUTPUT_PATH}")
PYEOF

chown ga:ga /home/ga/Desktop/scanned_uav_wing.stl
chmod 644 /home/ga/Desktop/scanned_uav_wing.stl

# Remove stale files
rm -f "$MODELS_DIR/reconstructed_wing.vsp3"
rm -f /tmp/openvsp_stl_reverse_engineering_result.json

# Kill any running OpenVSP
kill_openvsp

# Launch OpenVSP blank
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="