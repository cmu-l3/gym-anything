#!/bin/bash
echo "=== Setting up Attentional Network Test (ANT) Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time and generate nonce BEFORE deleting files
record_task_start
generate_nonce

# Ensure experiment directory exists
mkdir -p /home/ga/PsychoPyExperiments/data
mkdir -p /home/ga/PsychoPyExperiments/conditions
chown -R ga:ga /home/ga/PsychoPyExperiments

# Remove any pre-existing output files (after timestamp recorded)
rm -f /home/ga/PsychoPyExperiments/ant_experiment.psyexp 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/ant_conditions.csv 2>/dev/null || true
rm -f /home/ga/PsychoPyExperiments/conditions/ant_conditions.csv 2>/dev/null || true

# Record initial state
ls -la /home/ga/PsychoPyExperiments/ > /tmp/initial_file_state.txt 2>/dev/null || true

# ---- Fix PsychoPy config to prevent "Changes in" dialog ----
# The post_start hook has a race condition: it patches config while PsychoPy
# is running, then kills it, but PsychoPy overwrites on exit.
# Fix: kill PsychoPy, patch config, then restart cleanly.
PSYCHOPY_VER=$(python3 -c "import psychopy; print(psychopy.__version__)" 2>/dev/null | tr -d '[:space:]') || true
if [ -z "$PSYCHOPY_VER" ]; then
    PSYCHOPY_VER="2026.1.1"
fi

# Kill any running PsychoPy so it doesn't overwrite our config patch
pkill -f psychopy 2>/dev/null || true
sleep 3

# Patch appData.cfg to set lastVersion to current version
if [ -f /home/ga/.psychopy3/appData.cfg ]; then
    sed -i "s/lastVersion\s*=.*/lastVersion = $PSYCHOPY_VER/" /home/ga/.psychopy3/appData.cfg
    echo "Patched lastVersion to $PSYCHOPY_VER"
fi

# Ensure userPrefs disable startup dialogs
if [ -f /home/ga/.psychopy3/userPrefs.cfg ]; then
    sed -i 's/showStartupTips\s*=.*/showStartupTips = False/' /home/ga/.psychopy3/userPrefs.cfg
    sed -i 's/allowUsageStats\s*=.*/allowUsageStats = False/' /home/ga/.psychopy3/userPrefs.cfg
    sed -i 's/checkForUpdates\s*=.*/checkForUpdates = False/' /home/ga/.psychopy3/userPrefs.cfg
fi

# Start PsychoPy fresh with patched config
echo "Starting PsychoPy with patched config..."
su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 PSYCHOPY_USERDIR=/home/ga/.psychopy3 psychopy &"
wait_for_psychopy 90
sleep 5

# Dismiss any remaining dialogs (belt-and-suspenders)
dismiss_psychopy_dialogs
# Also try Escape key for any modal dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Builder window
sleep 2
BUILDER_WID=$(get_builder_window)
if [ -n "$BUILDER_WID" ]; then
    maximize_window "$BUILDER_WID"
    DISPLAY=:1 wmctrl -i -a "$BUILDER_WID"
    echo "Builder window maximized: $BUILDER_WID"
else
    # Fallback to any psychopy window
    maximize_psychopy
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== ANT Task setup complete ==="
echo "Task: Create ant_experiment.psyexp and ant_conditions.csv in /home/ga/PsychoPyExperiments/"
