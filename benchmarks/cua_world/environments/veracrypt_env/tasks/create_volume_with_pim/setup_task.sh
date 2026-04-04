#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Volume with PIM Task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Prepare the Source Document
# Ensure the document exists in Documents folder
if [ -f "/workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt" ]; then
    cp "/workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt" "/home/ga/Documents/SF312_Nondisclosure_Agreement.txt"
else
    # Fallback if asset missing (should not happen based on env spec, but safe practice)
    echo "This is a dummy SF-312 Nondisclosure Agreement for testing purposes." > "/home/ga/Documents/SF312_Nondisclosure_Agreement.txt"
    echo "CLASSIFIED INFORMATION NONDISCLOSURE AGREEMENT" >> "/home/ga/Documents/SF312_Nondisclosure_Agreement.txt"
fi

# Calculate checksum of source for later verification
sha256sum "/home/ga/Documents/SF312_Nondisclosure_Agreement.txt" | awk '{print $1}' > /tmp/source_file_checksum.txt

# 3. Clean State
# Remove any existing volume at the target path
rm -f /home/ga/Volumes/pim_volume.hc 2>/dev/null || true
# Ensure nothing is mounted at the target slot
veracrypt --text --dismount /home/ga/MountPoints/slot3 --non-interactive 2>/dev/null || true

# 4. App Setup
# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

# Wait for and focus window
if wait_for_window "VeraCrypt" 15; then
    wid=$(get_veracrypt_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        # Ensure it's not minimized
        DISPLAY=:1 wmctrl -i -r "$wid" -b remove,hidden,shaded 2>/dev/null || true
    fi
else
    echo "WARNING: VeraCrypt window not found"
fi

# 5. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="