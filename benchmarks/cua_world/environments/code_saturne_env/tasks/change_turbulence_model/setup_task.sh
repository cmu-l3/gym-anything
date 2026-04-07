#!/bin/bash
echo "=== Setting up change_turbulence_model task ==="

STUDY_DIR="/home/ga/CFD_Studies/TJunction_Study"

# Auto-detect case directory name (CASE1 or case1)
if [ -f "$STUDY_DIR/.case_dir_name" ]; then
    CASE_DIR=$(cat "$STUDY_DIR/.case_dir_name")
elif [ -d "$STUDY_DIR/CASE1" ]; then
    CASE_DIR="CASE1"
else
    CASE_DIR="case1"
fi
DATA_DIR="$STUDY_DIR/$CASE_DIR/DATA"
echo "Using case directory: $CASE_DIR"
echo "DATA directory: $DATA_DIR"

# Ensure the setup.xml is the original tutorial version (reset any prior changes)
if [ -f "/opt/code_saturne_tutorials/01_Simple_Junction/case1/DATA/setup.xml" ]; then
    cp /opt/code_saturne_tutorials/01_Simple_Junction/case1/DATA/setup.xml "$DATA_DIR/setup.xml"
    chown ga:ga "$DATA_DIR/setup.xml"
    echo "Reset setup.xml to original tutorial state"
fi

# Kill any existing Code_Saturne GUI instances
pkill -9 -f "code_saturne gui" 2>/dev/null || true
pkill -9 -f "cs_gui" 2>/dev/null || true
sleep 3

# Verify no leftover GUI process
while pgrep -f "code_saturne gui" > /dev/null 2>&1; do
    pkill -9 -f "code_saturne gui" 2>/dev/null || true
    sleep 1
done

# Launch the Code_Saturne GUI with the setup.xml file
echo "Launching Code_Saturne GUI..."
su - ga -c "cd $DATA_DIR && DISPLAY=:1 setsid code_saturne gui setup.xml > /tmp/cs_gui.log 2>&1 &"

# Wait for GUI to fully load
sleep 10

# Verify GUI is running
if pgrep -f "code_saturne gui" > /dev/null 2>&1; then
    echo "Code_Saturne GUI is running"
else
    echo "WARNING: Code_Saturne GUI may not have started, retrying..."
    su - ga -c "cd $DATA_DIR && DISPLAY=:1 setsid code_saturne gui setup.xml > /tmp/cs_gui.log 2>&1 &"
    sleep 10
fi

# Focus and maximize the GUI window
sleep 2
DISPLAY=:1 wmctrl -a "Code_Saturne" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Code_Saturne" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# List open windows for debugging
echo "Open windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Agent should: Navigate to Calculation features > Turbulence models,"
echo "change dropdown from 'k-epsilon Linear Production' to 'k-omega SST'"
