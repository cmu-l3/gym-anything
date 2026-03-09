#!/bin/bash
echo "=== Setting up Run Pass Sequence task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready"
fi

# Record initial state
echo "Recording initial state..."
INITIAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
printf '%s' "$INITIAL_COLLECTS" > /tmp/initial_collects_pass

# The pass sequence script content (saved for reference/API upload)
# Note: Uses str() concatenation instead of f-strings to avoid
# Monaco editor auto-bracket issues with curly braces during xdotool input
cat > /tmp/pass_sequence.py << 'SCRIPTEOF'
# Automated Satellite Pass Sequence
# This script performs a data collection pass on the INST target

from openc3.script import *

# Step 1: Verify satellite connectivity
print("Step 1: Verifying INST target connectivity...")
temp1 = tlm("INST HEALTH_STATUS TEMP1")
print("  Current TEMP1: " + str(temp1))
print("  INST target is responding normally.")

# Step 2: Send COLLECT command
print("Step 2: Initiating data collection...")
cmd("INST COLLECT with TYPE NORMAL, DURATION 5.0, TEMP 0.0")
print("  COLLECT command sent successfully.")

# Step 3: Wait for collection to complete
print("Step 3: Waiting for collection to complete...")
wait_check("INST HEALTH_STATUS COLLECTS > 0", 15)
print("  Collection confirmed!")

# Step 4: Read post-collection telemetry
print("Step 4: Reading post-collection telemetry...")
collects = tlm("INST HEALTH_STATUS COLLECTS")
temp1 = tlm("INST HEALTH_STATUS TEMP1")
temp2 = tlm("INST HEALTH_STATUS TEMP2")
print("  Total collections: " + str(collects))
print("  TEMP1: " + str(temp1))
print("  TEMP2: " + str(temp2))

print("")
print("=== Pass sequence completed successfully! ===")
SCRIPTEOF

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to the Script Runner tool
echo "Navigating to Script Runner..."
navigate_to_url "$OPENC3_URL/tools/scriptrunner"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Load the script into Script Runner editor using xdotool with window targeting
# The Monaco editor requires window-targeted key events to receive input correctly
echo "Loading script into Script Runner editor..."
sleep 3

# Click in the editor area to focus it (scaled from 1280x720: 300,227 -> 450,340)
DISPLAY=:1 xdotool mousemove 450 340 click 1
sleep 1

# Get the window ID for targeted key events
WID=$(DISPLAY=:1 xdotool getactivewindow)
echo "Targeting window: $WID"

# Clear any existing content
DISPLAY=:1 xdotool key --window $WID ctrl+a
sleep 0.3
DISPLAY=:1 xdotool key --window $WID Delete
sleep 0.5

# Type the script line by line using window-targeted xdotool type
# Uses str() concatenation instead of f-strings to avoid Monaco auto-bracket issues
type_line() {
    DISPLAY=:1 xdotool type --window $WID --delay 5 "$1"
    DISPLAY=:1 xdotool key --window $WID Return
}

type_line "# Automated Satellite Pass Sequence"
type_line "# This script performs a data collection pass on the INST target"
type_line ""
type_line "from openc3.script import *"
type_line ""
type_line "# Step 1: Verify satellite connectivity"
type_line 'print("Step 1: Verifying INST target connectivity...")'
type_line 'temp1 = tlm("INST HEALTH_STATUS TEMP1")'
type_line 'print("  Current TEMP1: " + str(temp1))'
type_line 'print("  INST target is responding normally.")'
type_line ""
type_line "# Step 2: Send COLLECT command"
type_line 'print("Step 2: Initiating data collection...")'
type_line 'cmd("INST COLLECT with TYPE NORMAL, DURATION 5.0, TEMP 0.0")'
type_line 'print("  COLLECT command sent successfully.")'
type_line ""
type_line "# Step 3: Wait for collection to complete"
type_line 'print("Step 3: Waiting for collection to complete...")'
type_line 'wait_check("INST HEALTH_STATUS COLLECTS > 0", 15)'
type_line 'print("  Collection confirmed!")'
type_line ""
type_line "# Step 4: Read post-collection telemetry"
type_line 'print("Step 4: Reading post-collection telemetry...")'
type_line 'collects = tlm("INST HEALTH_STATUS COLLECTS")'
type_line 'temp1 = tlm("INST HEALTH_STATUS TEMP1")'
type_line 'temp2 = tlm("INST HEALTH_STATUS TEMP2")'
type_line 'print("  Total collections: " + str(collects))'
type_line 'print("  TEMP1: " + str(temp1))'
type_line 'print("  TEMP2: " + str(temp2))'
type_line ""
# Last line - don't add Return after it
DISPLAY=:1 xdotool type --window $WID --delay 5 'print("=== Pass sequence completed successfully! ===")'
sleep 2

echo "Script loaded into editor"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Run Pass Sequence Task Setup Complete ==="
echo ""
echo "Task: The Script Runner is open with a satellite pass sequence script."
echo "Click the Start button (green play) to execute the script."
echo "Monitor execution and wait for successful completion."
echo ""
