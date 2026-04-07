#!/bin/bash
set -e
echo "=== Setting up PEBL fMRI Adaptation task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create experiment directory
mkdir -p /home/ga/pebl/experiments/fmri_gng
chown -R ga:ga /home/ga/pebl/experiments

SCRIPT_PATH="/home/ga/pebl/experiments/fmri_gng/gng_task.pbl"

# Generate the initial (unmodified) behavioral Go/No-Go PEBL script
cat > "$SCRIPT_PATH" << 'EOF'
define Start(p)
{
  # INITIAL VISUALS - Behavioral setup uses bright background
  gWin <- MakeWindow("white")
  gBGColor <- MakeColor("white")
  gFGColor <- MakeColor("black")

  # TIMING VARIABLES (in milliseconds)
  gStimDur <- 1000
  gISIDur <- 1000

  # RESPONSE MAPPING
  # Standard keyboard spacebar for behavioral testing
  gGoKey <- "<space>"
  
  # LOGGING
  gOutFile <- "gng_behavioral_log.csv"

  # --- DO NOT MODIFY BELOW THIS LINE ---
  fileOut <- FileOpenAppend(gOutFile)
  FilePrint(fileOut, "trial,stimulus,rt,correct")
  
  # Short dummy trial loop for parsing/testing
  loop(i, Sequence(1, 3, 1))
  {
     Wait(10)
  }
  
  FileClose(fileOut)
}
EOF

# Set permissions
chown ga:ga "$SCRIPT_PATH"
chmod 644 "$SCRIPT_PATH"
INITIAL_MTIME=$(stat -c %Y "$SCRIPT_PATH")
echo "$INITIAL_MTIME" > /tmp/initial_mtime.txt

# Start gedit with the script for the agent
su - ga -c "DISPLAY=:1 gedit '$SCRIPT_PATH' &"

# Wait for gedit window to appear
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "gedit\|gng_task.pbl"; then
        echo "Text editor window detected"
        break
    fi
    sleep 1
done

# Maximize the editor window
DISPLAY=:1 wmctrl -r "gng_task.pbl" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "gng_task.pbl" 2>/dev/null || true

# Give UI time to settle
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="