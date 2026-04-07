#!/bin/bash
echo "=== Setting up proteomics_trypsin_digest_ms task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean and prepare results directory
rm -rf /home/ga/UGENE_Data/proteomics_results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/proteomics_results
chown -R ga:ga /home/ga/UGENE_Data/proteomics_results

# Check input file and try to copy from assets if missing
if [ ! -f "/home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta" ]; then
    echo "WARNING: Input file not found, copying from assets..."
    mkdir -p /home/ga/UGENE_Data
    cp /workspace/assets/hemoglobin_beta_multispecies.fasta /home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta
    chown ga:ga /home/ga/UGENE_Data/hemoglobin_beta_multispecies.fasta
fi

# Start UGENE if not running
if ! pgrep -f "ugene" > /dev/null; then
    echo "Starting UGENE..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        break
    fi
    sleep 1
done

sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 2
fi

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="