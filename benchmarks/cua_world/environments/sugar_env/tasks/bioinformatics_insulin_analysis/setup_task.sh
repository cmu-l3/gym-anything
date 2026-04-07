#!/bin/bash
echo "=== Setting up bioinformatics_insulin_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any artifacts from previous runs
rm -f /home/ga/Documents/dna_analyzer.py 2>/dev/null || true
rm -f /home/ga/Documents/insulin_report.txt 2>/dev/null || true
rm -f /home/ga/Documents/insulin.fasta 2>/dev/null || true

# Generate the exact FASTA file using Python to guarantee known counts
python3 << 'PYEOF'
import random
import os

# Ensure consistent sequence generation
random.seed(42)

# Expected counts: A:97, C:172, G:131, T:65 -> Total: 465, GC: 65.16%
bases = ['A']*97 + ['C']*172 + ['G']*131 + ['T']*65
random.shuffle(bases)
seq = "".join(bases)

fasta_path = '/home/ga/Documents/insulin.fasta'
with open(fasta_path, 'w') as f:
    f.write(">NM_000207.3 Homo sapiens insulin (INS), transcript variant 1, mRNA\n")
    # Wrap at 70 characters
    for i in range(0, len(seq), 70):
        f.write(seq[i:i+70] + "\n")

os.chown(fasta_path, 1000, 1000) # ga user
PYEOF

# Record task start timestamp for verification
date +%s > /tmp/bio_start_ts
chmod 666 /tmp/bio_start_ts

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Sugar Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" > /dev/null 2>&1 &
sleep 10

# Take initial screenshot for evidence
su - ga -c "$SUGAR_ENV scrot /tmp/bio_task_start.png" 2>/dev/null || true

echo "=== Task setup complete ==="