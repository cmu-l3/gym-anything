#!/bin/bash
echo "=== Setting up load_playback_recording task ==="

source /workspace/utils/openbci_utils.sh || true

# Kill any running instance
kill_openbci

# Ensure the EEG playback file is in place
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p ${RECORDINGS_DIR}"

# Copy the correctly formatted EEG data file (v5 format compatible with OpenBCI GUI)
# The file OpenBCI_GUI-v5-EEGEyesOpen.txt has the proper header:
#   %Board = OpenBCI_GUI$BoardCytonSerial
# and 24 columns per data row (required by getDataSourcePlaybackClassFromFile).
# We copy it as OpenBCI-EEG-S001-EyesOpen.txt so agents see the expected filename.
if [ ! -f "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    if [ -f "/workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt" ]; then
        cp /workspace/data/OpenBCI_GUI-v5-EEGEyesOpen.txt "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
        chown ga:ga "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
        echo "Copied formatted EEG recording file to Recordings folder"
    elif [ -f "/workspace/data/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
        cp /workspace/data/OpenBCI-EEG-S001-EyesOpen.txt "${RECORDINGS_DIR}/"
        chown ga:ga "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
        echo "Copied EEG recording file (original format)"
    else
        echo "WARNING: EEG recording file not found at /workspace/data/"
        echo "Playback task will not have data available"
    fi
else
    echo "EEG recording file already present"
fi

# Verify file exists and show info
if [ -f "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt" ]; then
    LINES=$(wc -l < "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt")
    SIZE=$(wc -c < "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt")
    echo "Recording file: ${LINES} lines, ${SIZE} bytes"
    # Verify header format
    HEAD=$(head -4 "${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt")
    echo "File header:"
    echo "${HEAD}"
fi

# Launch OpenBCI GUI at the Control Panel (not started)
echo "Launching OpenBCI GUI at Control Panel..."
launch_openbci

echo "=== Task setup complete ==="
echo "EEG recording available at: ${RECORDINGS_DIR}/OpenBCI-EEG-S001-EyesOpen.txt"
echo "Agent should: 1) Select PLAYBACK mode, 2) Select the EEG file, 3) Click START SESSION"
