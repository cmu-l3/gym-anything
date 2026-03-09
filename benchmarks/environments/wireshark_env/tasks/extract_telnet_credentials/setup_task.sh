#!/bin/bash
set -e
echo "=== Setting up extract_telnet_credentials task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Remove any previous report file
rm -f /home/ga/Documents/telnet_report.txt
rm -f /tmp/task_result.json

# Verify the telnet pcap file exists and is valid
PCAP_FILE="/home/ga/Documents/captures/telnet-cooked.pcap"
if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: telnet-cooked.pcap is missing or empty!"
    exit 1
fi

# Pre-compute ground truth and store it hidden from agent
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Extract the telnet stream to find credentials
# We use Python to robustly parse the Telnet stream for login/password prompts
echo "Extracting ground truth credentials..."

python3 << 'PYEOF'
import re
import subprocess
import os

pcap_file = "/home/ga/Documents/captures/telnet-cooked.pcap"
gt_dir = "/var/lib/wireshark_ground_truth"
gt_file = os.path.join(gt_dir, "credentials.txt")

# Get TCP stream 0 (standard for this capture)
cmd = ["tshark", "-r", pcap_file, "-z", "follow,tcp,ascii,0", "-q"]
try:
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    stream_content = result.stdout
except subprocess.CalledProcessError as e:
    print(f"Error extracting stream: {e}")
    exit(1)

# Heuristic parsing for Telnet login
username = ""
password = ""

lines = stream_content.split('\n')
for i, line in enumerate(lines):
    clean_line = line.strip().lower()
    
    # Look for username prompt
    if "login:" in clean_line or "username:" in clean_line:
        # Check if username is on the same line (rare in telnet due to echo) or next lines
        # In telnet-cooked.pcap, user types 'f', 'a', 'k', 'e' which echoes back
        # We look for the line AFTER the prompt that contains the input
        # Note: This is specific to the sample capture structure
        
        # Simple heuristic: Look for the first non-empty line after prompt that isn't 'Password:'
        for j in range(i+1, min(i+10, len(lines))):
            cand = lines[j].strip()
            if cand and "password" not in cand.lower() and "last login" not in cand.lower():
                # In captured streams, you often see the typed characters. 
                # For this specific file, the username is 'fake' and password is 'user'
                # But let's try to extract dynamically.
                # If we fail, we fallback to known values for this specific standard dataset.
                username = cand
                break
    
    # Look for password prompt
    if "password:" in clean_line:
        for j in range(i+1, min(i+10, len(lines))):
            cand = lines[j].strip()
            if cand and "login" not in cand.lower() and "domain" not in cand.lower():
                password = cand
                break

# Fallback for the known "telnet-cooked.pcap" file if heuristic fails
# This file is standard: user 'fake', password 'user'
if not username or len(username) > 20: 
    username = "fake"
if not password or len(password) > 20:
    password = "user"

print(f"Detected credentials - User: {username}, Pass: {password}")

with open(gt_file, "w") as f:
    f.write(f"username: {username}\n")
    f.write(f"password: {password}\n")
PYEOF

# Start Wireshark (empty) so the agent has to load the file
# This ensures they know how to open files
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
            echo "Wireshark started."
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Dismiss any startup dialogs (Welcome screen is fine, but dismiss 'Lua' or update errors)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="