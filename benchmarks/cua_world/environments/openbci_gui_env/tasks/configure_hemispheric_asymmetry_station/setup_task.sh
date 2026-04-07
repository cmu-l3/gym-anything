#!/bin/bash
echo "=== Setting up configure_hemispheric_asymmetry_station task ==="

source /workspace/utils/openbci_utils.sh || true

# Create standard directories
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Clean up previous run artifacts BEFORE recording timestamps
rm -f /home/ga/Documents/asymmetry_station_report.txt 2>/dev/null || true

# Record initial state for verification (after cleanup, before app launch)
echo "$(date +%s)" > /tmp/task_start_time.txt
count_screenshots > /tmp/hemispheric_initial_screenshot_count
ls /home/ga/Documents/OpenBCI_GUI/Settings/ 2>/dev/null > /tmp/hemispheric_initial_settings_list || true
ls -1 /home/ga/Documents/OpenBCI_GUI/Recordings/ 2>/dev/null > /tmp/hemispheric_initial_recordings_list || true

# Launch OpenBCI GUI with Synthetic session pre-started and data streaming.
launch_openbci_synthetic

# Verify session actually started; if not, retry with robust approach.
# The GUI sometimes needs more time to render the Control Panel before clicks register.
if ! grep -q "\[SUCCESS\]: Session started!" /tmp/openbci_task.log 2>/dev/null; then
    echo "WARNING: Session did not start on first attempt. Waiting for GUI to settle..."

    # Wait for the GUI window title to include the version string (sign it's fully rendered)
    for i in $(seq 1 15); do
        if su - ga -c 'DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null' | grep -qi "v5"; then
            echo "GUI Control Panel fully rendered after extra ${i}s wait"
            break
        fi
        sleep 2
    done
    sleep 3  # Extra settle time after rendering

    for attempt in 1 2 3 4 5; do
        echo "Retry attempt $attempt..."
        # Click SYNTHETIC (confirmed via visual grounding at 180,209 in 1920x1080)
        su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove --sync 180 209; sleep 0.3; xdotool click 1' 2>/dev/null || true
        sleep 2
        # Click START SESSION (confirmed via visual grounding at 200,281 in 1920x1080)
        su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool mousemove --sync 200 281; sleep 0.3; xdotool click 1' 2>/dev/null || true
        sleep 5
        if grep -q "\[SUCCESS\]: Session started!" /tmp/openbci_task.log 2>/dev/null; then
            echo "Session started on retry attempt $attempt"
            sleep 2
            # Start data stream with SPACE
            su - ga -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; xdotool key space' 2>/dev/null || true
            sleep 3
            break
        fi
    done
fi

if grep -q "\[SUCCESS\]: Session started!" /tmp/openbci_task.log 2>/dev/null; then
    echo "=== Task setup complete: Synthetic session running, data streaming ==="
else
    echo "WARNING: Could not confirm session start. Agent may need to start session manually."
fi

echo "Agent should configure 6-panel layout with dual Band Power (left/right hemisphere),"
echo "filters, LSL streaming, recording, Expert Mode screenshot, and settings save."
