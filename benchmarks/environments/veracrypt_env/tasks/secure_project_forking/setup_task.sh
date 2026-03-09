#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Secure Project Forking Task ==="

# record start time
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
echo "Cleaning up volumes and keyfiles..."
veracrypt --text --dismount --non-interactive 2>/dev/null || true
rm -f /home/ga/Volumes/project_alpha.hc 2>/dev/null || true
rm -f /home/ga/Volumes/project_beta.hc 2>/dev/null || true
rm -f /home/ga/Keyfiles/master_key 2>/dev/null || true

# Ensure directories exist
mkdir -p /home/ga/Volumes
mkdir -p /home/ga/Keyfiles
chown -R ga:ga /home/ga/Volumes /home/ga/Keyfiles

# Ensure sample data exists
if [ ! -f /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt ]; then
    echo "Creating sample data..."
    mkdir -p /workspace/assets/sample_data
    echo "CONFIDENTIAL: SF312 NON-DISCLOSURE AGREEMENT" > /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt
    echo "This data must be protected inside the encrypted volume." >> /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt
fi

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Focus VeraCrypt
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Maximize
    DISPLAY=:1 wmctrl -r "VeraCrypt" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="