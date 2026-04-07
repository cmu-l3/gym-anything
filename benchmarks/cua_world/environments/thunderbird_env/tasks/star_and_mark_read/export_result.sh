#!/bin/bash
set -e
echo "=== Exporting star_and_mark_read result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE closing
take_screenshot /tmp/task_final.png

# Check if Thunderbird was running
APP_RUNNING="false"
if is_thunderbird_running; then
    APP_RUNNING="true"
fi

# Gracefully close Thunderbird to ensure mbox cache is flushed to disk
echo "Closing Thunderbird to flush mbox..."
su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
sleep 3
if is_thunderbird_running; then
    pkill -f thunderbird 2>/dev/null || true
    sleep 2
fi

# Parse mbox into JSON for verification
cat > /tmp/parse_mbox.py << 'EOF'
import mailbox
import json
import os

mbox_path = "/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox"
results = []
mbox_mtime = 0

if os.path.exists(mbox_path):
    mbox_mtime = os.path.getmtime(mbox_path)
    mbox = mailbox.mbox(mbox_path)
    for msg in mbox:
        status = msg.get('X-Mozilla-Status', '0000')
        try:
            status_int = int(status, 16)
        except ValueError:
            status_int = 0
            
        is_read = bool(status_int & 0x0001)
        is_starred = bool(status_int & 0x0004)
        subject = msg.get('Subject', '')
        
        results.append({
            "subject": subject,
            "is_read": is_read,
            "is_starred": is_starred
        })

# Read task start time for anti-gaming checks
start_time = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        try:
            start_time = float(f.read().strip())
        except ValueError:
            pass

with open("/tmp/task_result.json", "w") as f:
    json.dump({
        "emails": results,
        "mbox_mtime": mbox_mtime,
        "task_start_time": start_time,
        "app_was_running": True if os.environ.get("APP_RUNNING") == "true" else False
    }, f)
print("Mbox parsing complete.")
EOF

export APP_RUNNING
python3 /tmp/parse_mbox.py

# Set broad permissions so the host verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="