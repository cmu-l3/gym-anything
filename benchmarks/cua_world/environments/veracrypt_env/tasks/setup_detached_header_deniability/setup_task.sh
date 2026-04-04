#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Detached Header Deniability Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create working directory
mkdir -p /home/ga/SecureTransport
chown ga:ga /home/ga/SecureTransport

# Ensure sample data exists
if [ ! -f /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt ]; then
    echo "Restoring sample data..."
    mkdir -p /workspace/assets/sample_data
    echo "TOP SECRET DATA CONTENT" > /workspace/assets/sample_data/SF312_Nondisclosure_Agreement.txt
fi

# Ensure VeraCrypt is running for the agent
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 5
fi

# Focus VeraCrypt
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Clean up any previous attempts (for retries)
rm -f /home/ga/SecureTransport/ghost_data.hc
rm -f /home/ga/SecureTransport/ghost_header.vc

echo "=== Setup Complete ==="