#!/bin/bash
echo "=== Setting up modify_hohmann_transfer task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Kill any existing GMAT instances
pkill -f "/opt/GMAT/bin/GMAT" 2>/dev/null || true
sleep 2

# Find the Hohmann Transfer sample mission
HOHMANN_SCRIPT=""
for candidate in \
    "/opt/GMAT/samples/Ex_HohmannTransfer.script" \
    "/home/ga/Documents/missions/Ex_HohmannTransfer.script" \
    "/opt/GMAT/samples/Navigation/Ex_HohmannTransfer.script"; do
    if [ -f "$candidate" ]; then
        HOHMANN_SCRIPT="$candidate"
        break
    fi
done

# If not found by exact name, search for it
if [ -z "$HOHMANN_SCRIPT" ]; then
    echo "Searching for Hohmann Transfer script..."
    HOHMANN_SCRIPT=$(find /opt/GMAT -name "*[Hh]ohmann*" -name "*.script" 2>/dev/null | head -1)
fi

# If still not found, search in samples for any transfer script
if [ -z "$HOHMANN_SCRIPT" ]; then
    echo "Searching for any transfer script..."
    HOHMANN_SCRIPT=$(find /opt/GMAT/samples -name "*.script" 2>/dev/null | head -1)
fi

if [ -z "$HOHMANN_SCRIPT" ]; then
    echo "ERROR: Could not find any GMAT sample script"
    echo "Available files in /opt/GMAT/samples/:"
    find /opt/GMAT/samples -type f 2>/dev/null || echo "No samples directory"
    exit 1
fi

echo "Using mission script: $HOHMANN_SCRIPT"

# Copy the script to user's working directory so modifications can be saved
WORKING_SCRIPT="/home/ga/Documents/missions/HohmannTransfer_task.script"
cp "$HOHMANN_SCRIPT" "$WORKING_SCRIPT"

# The sample script uses default spacecraft (Cartesian, SMA ~7191 km).
# We need to explicitly set Keplerian elements so the task starts with SMA = 6678.14 km
# (300 km LEO altitude). Insert spacecraft configuration right after "Create Spacecraft DefaultSC;"
sed -i '/Create Spacecraft DefaultSC;/a\
GMAT DefaultSC.DateFormat = UTCGregorian;\
GMAT DefaultSC.Epoch = '\''01 Jan 2024 12:00:00.000'\'';\
GMAT DefaultSC.CoordinateSystem = EarthMJ2000Eq;\
GMAT DefaultSC.DisplayStateType = Keplerian;\
GMAT DefaultSC.SMA = 6678.14;\
GMAT DefaultSC.ECC = 0.001;\
GMAT DefaultSC.INC = 28.5;\
GMAT DefaultSC.RAAN = 0;\
GMAT DefaultSC.AOP = 0;\
GMAT DefaultSC.TA = 0;' "$WORKING_SCRIPT"

chown ga:ga "$WORKING_SCRIPT"

# Verify SMA was injected correctly
INITIAL_SMA=$(grep -oP 'SMA\s*=\s*\K[0-9.]+' "$WORKING_SCRIPT" 2>/dev/null | head -1)
echo "Initial SMA value in script: ${INITIAL_SMA:-unknown}"
if [ "${INITIAL_SMA}" != "6678.14" ]; then
    echo "WARNING: Expected SMA=6678.14 but found ${INITIAL_SMA:-nothing}"
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch GMAT with the Hohmann Transfer script
echo "Launching GMAT with Hohmann Transfer mission..."
launch_gmat "$WORKING_SCRIPT"

# Wait for GMAT window
echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 90)
if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5

    # Dismiss any startup dialogs
    dismiss_gmat_dialogs
    sleep 2

    # Maximize and focus
    focus_gmat_window
    sleep 1

    # Kill any Firefox that GMAT may have opened
    pkill -f "firefox" 2>/dev/null || true

    echo "GMAT is ready with Hohmann Transfer mission loaded"
else
    echo "WARNING: GMAT window did not appear, checking process..."
    ps aux | grep -i gmat | grep -v grep || true
    cat /tmp/gmat_task.log 2>/dev/null | tail -20 || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved to /tmp/task_initial_screenshot.png"

echo "=== modify_hohmann_transfer task setup complete ==="
