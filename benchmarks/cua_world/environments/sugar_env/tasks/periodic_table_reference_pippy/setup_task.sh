#!/bin/bash
echo "=== Setting up periodic_table_reference_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Generate real periodic table CSV with required elements + decoys
python3 << 'EOF'
import csv

elements_data = [
    (1, 'H', 'Hydrogen', 1.008, '1s1', 1, 1, 'Gas'),
    (2, 'He', 'Helium', 4.0026, '1s2', 18, 1, 'Gas'),
    (6, 'C', 'Carbon', 12.011, '[He] 2s2 2p2', 14, 2, 'Solid'),
    (7, 'N', 'Nitrogen', 14.007, '[He] 2s2 2p3', 15, 2, 'Gas'),
    (8, 'O', 'Oxygen', 15.999, '[He] 2s2 2p4', 16, 2, 'Gas'),
    (10, 'Ne', 'Neon', 20.180, '[He] 2s2 2p6', 18, 2, 'Gas'),
    (11, 'Na', 'Sodium', 22.990, '[Ne] 3s1', 1, 3, 'Solid'),
    (13, 'Al', 'Aluminum', 26.982, '[Ne] 3s2 3p1', 13, 3, 'Solid'),
    (14, 'Si', 'Silicon', 28.085, '[Ne] 3s2 3p2', 14, 3, 'Solid'),
    (17, 'Cl', 'Chlorine', 35.45, '[Ne] 3s2 3p5', 17, 3, 'Gas'),
    (18, 'Ar', 'Argon', 39.95, '[Ne] 3s2 3p6', 18, 3, 'Gas'),
    (20, 'Ca', 'Calcium', 40.078, '[Ar] 4s2', 2, 4, 'Solid'),
    (26, 'Fe', 'Iron', 55.845, '[Ar] 3d6 4s2', 8, 4, 'Solid'),
    (29, 'Cu', 'Copper', 63.546, '[Ar] 3d10 4s1', 11, 4, 'Solid'),
    (30, 'Zn', 'Zinc', 65.38, '[Ar] 3d10 4s2', 12, 4, 'Solid'),
    (47, 'Ag', 'Silver', 107.868, '[Kr] 4d10 5s1', 11, 5, 'Solid'),
    (50, 'Sn', 'Tin', 118.710, '[Kr] 4d10 5s2 5p2', 14, 5, 'Solid'),
    (79, 'Au', 'Gold', 196.967, '[Xe] 4f14 5d10 6s1', 11, 6, 'Solid'),
    (80, 'Hg', 'Mercury', 200.592, '[Xe] 4f14 5d10 6s2', 12, 6, 'Liquid'),
    (82, 'Pb', 'Lead', 207.2, '[Xe] 4f14 5d10 6s2 6p2', 14, 6, 'Solid')
]

# Sort by atomic number to simulate real dataset
elements_data.sort(key=lambda x: x[0])

with open('/home/ga/Documents/elements.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['AtomicNumber', 'Symbol', 'Name', 'AtomicMass', 'ElectronConfiguration', 'Group', 'Period', 'Phase'])
    for row in elements_data:
        writer.writerow(row)
EOF
chown ga:ga /home/ga/Documents/elements.csv

# Remove any pre-existing output files
rm -f /home/ga/Documents/periodic_lookup.py 2>/dev/null || true
rm -f /home/ga/Documents/element_report.txt 2>/dev/null || true

# Record task start timestamp (anti-gaming)
date +%s > /tmp/periodic_pippy_start_ts
chmod 666 /tmp/periodic_pippy_start_ts

# Return to home view, then launch Pippy
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3
echo "Launching Pippy activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Pippy" &
sleep 12

# Take initial screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/pippy_task_start.png" 2>/dev/null || true

echo "=== periodic_table_reference_pippy task setup complete ==="