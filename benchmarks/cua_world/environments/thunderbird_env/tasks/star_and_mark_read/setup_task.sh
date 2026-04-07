#!/bin/bash
set -e
echo "=== Setting up star_and_mark_read task ==="

source /workspace/scripts/task_utils.sh

# Make sure Thunderbird is closed before modifying files
close_thunderbird 2>/dev/null || true
sleep 2

# Modify Inbox mbox to add EMBARGOED subjects and mark all unread
cat > /tmp/prepare_mbox.py << 'EOF'
import mailbox
import os

mbox_path = "/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox"
if not os.path.exists(mbox_path):
    print(f"Inbox not found at {mbox_path}")
    exit(1)

mbox = mailbox.mbox(mbox_path)
mbox.lock()
try:
    keys = mbox.keys()
    for i, key in enumerate(keys):
        msg = mbox[key]

        # Mark as unread and unstarred (0000)
        if 'X-Mozilla-Status' in msg:
            msg.replace_header('X-Mozilla-Status', '0000')
        else:
            msg.add_header('X-Mozilla-Status', '0000')

        # Add EMBARGOED to the first 3 emails
        if i < 3:
            old_sub = msg.get('Subject', 'No Subject').replace('\r', '').replace('\n', '')
            if 'EMBARGOED' not in old_sub:
                new_sub = f"EMBARGOED: {old_sub}"
                if 'Subject' in msg:
                    msg.replace_header('Subject', new_sub)
                else:
                    msg.add_header('Subject', new_sub)

        mbox[key] = msg
    mbox.flush()
finally:
    mbox.unlock()
print("Mbox preparation complete.")
EOF

python3 /tmp/prepare_mbox.py

# Delete index file so Thunderbird rebuilds it from the modified mbox
rm -f "/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox.msf"

# IMPORTANT: Record task start time AFTER we modify the mbox, 
# so we can reliably detect if the agent modifies it further.
sleep 1
date +%s > /tmp/task_start_time.txt

# Start Thunderbird
start_thunderbird

# Wait for window and maximize
wait_for_thunderbird_window 30
sleep 2
maximize_thunderbird

# Click center to ensure window focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="