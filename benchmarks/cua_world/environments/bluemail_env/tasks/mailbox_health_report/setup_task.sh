#!/bin/bash
set -e
echo "=== Setting up mailbox_health_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/mailbox_health_report.txt
# Clear drafts to ensure we detect the new one
rm -f /home/ga/Maildir/.Drafts/cur/* /home/ga/Maildir/.Drafts/new/* 2>/dev/null || true

# 2. Establish Ground Truth Counts
# We use Python to get accurate counts from Maildir to compare against agent's report later
python3 << 'PYEOF'
import os
import json

maildir_root = "/home/ga/Maildir"

def count_folder(path):
    if not os.path.exists(path):
        return 0
    # Count files in cur and new
    return len([f for f in os.listdir(os.path.join(path, 'cur')) if os.path.isfile(os.path.join(path, 'cur', f))]) + \
           len([f for f in os.listdir(os.path.join(path, 'new')) if os.path.isfile(os.path.join(path, 'new', f))])

counts = {
    "inbox": count_folder(maildir_root),
    "junk": count_folder(os.path.join(maildir_root, ".Junk")),
    "drafts": count_folder(os.path.join(maildir_root, ".Drafts")),
    "sent": count_folder(os.path.join(maildir_root, ".Sent")),
    "trash": count_folder(os.path.join(maildir_root, ".Trash"))
}

with open("/tmp/initial_counts.json", "w") as f:
    json.dump(counts, f)
print(f"Ground truth counts: {counts}")
PYEOF

# 3. Ensure BlueMail is running and ready
if ! is_bluemail_running; then
    echo "Starting BlueMail..."
    start_bluemail
fi

wait_for_bluemail_window 60
maximize_bluemail
sleep 2

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="