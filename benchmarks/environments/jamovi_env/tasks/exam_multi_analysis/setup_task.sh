#!/bin/bash
echo "=== Setting up exam_multi_analysis task ==="

# Kill any running Jamovi instance
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

# Ensure the dataset exists (copy from source if missing)
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"
if [ ! -f "$DATASET" ]; then
    echo "Copying dataset from /opt/jamovi_datasets..."
    mkdir -p /home/ga/Documents/Jamovi
    cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATASET"
    chown ga:ga "$DATASET"
fi

echo "Dataset ready: $DATASET"
head -3 "$DATASET"
wc -l "$DATASET"

# Record baseline: remove any previous output file so we start clean
OMV_FILE="/home/ga/Documents/Jamovi/ExamAnalysis.omv"
if [ -f "$OMV_FILE" ]; then
    echo "Removing previous output file: $OMV_FILE"
    rm -f "$OMV_FILE"
fi

# Record baseline timestamp for verifier
date +%s > /tmp/exam_multi_analysis_start_timestamp
echo "Baseline recorded: no .omv file exists, timestamp saved"

# Open Jamovi with the ExamAnxiety dataset pre-loaded.
# Uses setsid so the process survives when su exits.
# --no-sandbox and --disable-gpu are set inside the launcher script.
su - ga -c "setsid /usr/local/bin/launch-jamovi $DATASET > /tmp/jamovi_task.log 2>&1 &"
sleep 20

# Dismiss any lingering dialogs (update notifier, welcome screen)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize the Jamovi window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
SCREENSHOT="/tmp/exam_multi_analysis_init.png"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT'" 2>/dev/null || true
if [ -f "$SCREENSHOT" ]; then
    echo "Initial screenshot saved: $SCREENSHOT"
else
    echo "Warning: Could not capture initial screenshot"
fi

echo "=== exam_multi_analysis task setup complete ==="
