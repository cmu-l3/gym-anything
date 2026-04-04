#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Camouflaged Volume Task ==="

# 1. Clean up any previous run artifacts
rm -f /home/ga/Volumes/legacy_driver_backup.iso 2>/dev/null || true
rm -f /home/ga/Documents/exploit_poc.py 2>/dev/null || true

# 2. Create the sensitive file to be hidden
cat > /home/ga/Documents/exploit_poc.py << 'EOF'
#!/usr/bin/env python3
import socket
import struct

def check_target(ip, port):
    print(f"Scanning target {ip}:{port}...")
    # This is a dummy PoC for educational purposes
    payload = struct.pack("<I", 0xDEADBEEF)
    print("Payload ready.")
    return True

if __name__ == "__main__":
    check_target("192.168.1.100", 8080)
EOF
chmod 644 /home/ga/Documents/exploit_poc.py

# 3. Ensure VeraCrypt is running and visible
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# Focus VeraCrypt
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 4. Record task start time (used to ensure file *creation* happened during task, 
#    even if mtime is backdated later)
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="