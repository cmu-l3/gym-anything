#!/bin/bash
set -e
echo "=== Setting up insulin_inverted_repeat_analysis task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean previous task state and prepare directories
rm -rf /home/ga/UGENE_Data/repeat_analysis 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/repeat_analysis
chown -R ga:ga /home/ga/UGENE_Data/repeat_analysis

# 3. Ensure input data exists (fallback to bundled assets if needed)
INPUT_FILE="/home/ga/UGENE_Data/human_insulin_gene.gb"
if [ ! -s "$INPUT_FILE" ]; then
    echo "Restoring human_insulin_gene.gb from assets..."
    cp /workspace/assets/human_insulin_gene.gb "$INPUT_FILE" 2>/dev/null || true
    chown ga:ga "$INPUT_FILE" 2>/dev/null || true
fi

if [ ! -s "$INPUT_FILE" ]; then
    echo "WARNING: Input file not found at $INPUT_FILE"
else
    echo "Input file verified: $INPUT_FILE"
fi

# 4. Kill any existing UGENE instances for a clean start
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# 5. Launch UGENE
echo "Starting UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 6. Wait for UGENE window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected"
        break
    fi
    sleep 2
done

# Give the UI a moment to fully render
sleep 4

# 7. Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# 8. Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Take initial state screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="