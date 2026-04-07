#!/bin/bash
echo "=== Setting up BRCA1 CRISPR Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean and set up directories
mkdir -p /home/ga/UGENE_Data/crispr/results
rm -rf /home/ga/UGENE_Data/crispr/results/*
rm -f /tmp/task_result.json

# Generate a biologically plausible 3.4kb sequence (simulating BRCA1 Exon 11)
# GC content roughly 40%, which ensures plenty of NGG PAM sites.
python3 -c '
import random
random.seed(12345)
bases = ["A", "C", "G", "T"]
weights = [0.3, 0.2, 0.2, 0.3]
seq = "".join(random.choices(bases, weights=weights, k=3400))
with open("/home/ga/UGENE_Data/crispr/BRCA1_exon11.fasta", "w") as f:
    f.write(">BRCA1_exon11_synthetic_region\n")
    for i in range(0, len(seq), 80):
        f.write(seq[i:i+80] + "\n")
'

# Set permissions
chown -R ga:ga /home/ga/UGENE_Data/crispr

# Start UGENE
echo "Starting UGENE..."
pkill -f ugene 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE to load
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
done
sleep 5

# Dismiss startup dialogs and maximize
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "=== Setup complete ==="