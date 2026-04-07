#!/bin/bash
echo "=== Setting up community_champion_identification task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean up previous task artifacts
# ============================================================
MAILDIR="/home/ga/Maildir"

# Remove Champion-Candidate folder if it exists
rm -rf "$MAILDIR/.Champion-Candidate" 2>/dev/null || true

# Clear Drafts and Sent to ensure clean verification
rm -f "$MAILDIR/.Drafts/cur/"* "$MAILDIR/.Drafts/new/"* 2>/dev/null || true
rm -f "$MAILDIR/.Sent/cur/"* "$MAILDIR/.Sent/new/"* 2>/dev/null || true

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 2. Ensure BlueMail is running and ready
# ============================================================
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60

# Maximize
maximize_bluemail
sleep 2

# ============================================================
# 3. Verify Data Sufficiency (Internal Check)
# ============================================================
# We need at least one sender with >= 2 emails for the task to be solvable.
# We'll check the inbox now.
python3 << 'PYEOF'
import os
import re
import collections

maildir = "/home/ga/Maildir"
senders = []

for subdir in ['cur', 'new']:
    path = os.path.join(maildir, subdir)
    if os.path.exists(path):
        for fname in os.listdir(path):
            try:
                with open(os.path.join(path, fname), 'r', errors='ignore') as f:
                    content = f.read()
                    # Simple regex to find From: header
                    match = re.search(r'^From:.*?<([^>]+)>', content, re.MULTILINE | re.IGNORECASE)
                    if not match:
                        match = re.search(r'^From:\s*([^\s<]+@[\w.-]+)', content, re.MULTILINE | re.IGNORECASE)
                    
                    if match:
                        senders.append(match.group(1).lower())
            except:
                pass

counts = collections.Counter(senders)
valid_targets = {k: v for k, v in counts.items() if v >= 2}

print(f"DEBUG: Found {len(valid_targets)} valid targets with >= 2 emails.")
if len(valid_targets) == 0:
    print("WARNING: No repeat senders found! Task may be impossible.")
else:
    print(f"DEBUG: Targets: {list(valid_targets.keys())}")
PYEOF

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="