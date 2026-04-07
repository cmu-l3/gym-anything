#!/bin/bash
echo "=== Setting up configure_timeseries_window task ==="

source /workspace/utils/openbci_utils.sh || true

su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots"
su - ga -c "mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings"

# Clean up previous result file
rm -f /home/ga/Documents/OpenBCI_GUI/timeseries_config.txt

# Ensure EEG playback data files exist
for src_file in "OpenBCI-EEG-S001-EyesOpen.txt"; do
    DEST="/home/ga/Documents/OpenBCI_GUI/Recordings/$src_file"
    if [ ! -f "$DEST" ]; then
        for candidate in "/opt/openbci_data/$src_file" "/workspace/data/$src_file" "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt"; do
            if [ -f "$candidate" ]; then
                cp "$candidate" "$DEST"
                chown ga:ga "$DEST"
                echo "Copied $src_file from $candidate"
                break
            fi
        done
    fi
done

# Launch OpenBCI GUI at Control Panel
launch_openbci

echo "=== Task setup complete ==="
