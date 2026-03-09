#!/bin/bash
set -e
echo "=== Setting up BEM Characteristic TSR Sweep task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Anti-gaming: Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Clean state: Remove artifacts and ensure directories
rm -f /home/ga/Documents/projects/cp_tsr_results.txt 2>/dev/null || true
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects
rm -f /tmp/qblade_task.log 2>/dev/null || true

# 3. Locate Sample Project
# We prefer the NREL 5MW or any bundled sample project
SAMPLE_PROJECT=""
POSSIBLE_LOCATIONS=(
    "/home/ga/Documents/sample_projects/NREL_5MW_Reference_Turbine.wpa"
    "/home/ga/Documents/sample_projects/*.wpa"
    "/opt/qblade/sample_projects/*.wpa"
)

for loc in "${POSSIBLE_LOCATIONS[@]}"; do
    # Expand glob
    for f in $loc; do
        if [ -f "$f" ]; then
            SAMPLE_PROJECT="$f"
            break 2
        fi
    done
done

# If found in /opt but not in user doc, copy it
if [[ "$SAMPLE_PROJECT" == /opt* ]]; then
    cp "$SAMPLE_PROJECT" /home/ga/Documents/sample_projects/
    SAMPLE_PROJECT="/home/ga/Documents/sample_projects/$(basename "$SAMPLE_PROJECT")"
    chown ga:ga "$SAMPLE_PROJECT"
fi

if [ -z "$SAMPLE_PROJECT" ]; then
    echo "WARNING: No sample project found. Agent will start with empty QBlade."
else
    echo "Using sample project: $SAMPLE_PROJECT"
fi

# 4. Launch QBlade
echo "Launching QBlade..."
# Use shared launch function if available, otherwise manual
if type launch_qblade &>/dev/null; then
    launch_qblade "$SAMPLE_PROJECT"
else
    # Fallback manual launch
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    if [ -n "$QBLADE_BIN" ]; then
        QBLADE_DIR=$(dirname "$QBLADE_BIN")
        su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; cd '$QBLADE_DIR' && '$QBLADE_BIN' '$SAMPLE_PROJECT' > /tmp/qblade_task.log 2>&1 &"
    fi
fi

# 5. Wait for window and maximize
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "QBlade" >/dev/null; then
        echo "QBlade window detected."
        break
    fi
    sleep 1
done

# Maximize to ensure buttons are visible
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup "Welcome" or "Update" dialogs if they exist (press Esc)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture Initial State Screenshot (Evidence)
take_screenshot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="