#!/bin/bash
set -e
echo "=== Setting up Critical Bug Thread Isolation Task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ==============================================================================
# 1. Clean Slate Setup
# ==============================================================================

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Ensure BlueMail is running (preserves account config)
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Clear existing email folders to ensure clean state
rm -f "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Critical-Thread" 2>/dev/null || true
# Remove other custom folders
find "$MAILDIR" -maxdepth 1 -type d -name ".*" ! -name ".Junk" ! -name ".Trash" ! -name ".Drafts" ! -name ".Sent" -exec rm -rf {} +

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'EOF'
Junk
Drafts
Sent
Trash
EOF

# ==============================================================================
# 2. Data Generation (Scenario Construction)
# ==============================================================================
# We need to construct a scenario where one Bug ID has significantly more emails
# than others. We will use real email content but modify headers to create threads.

# Parameters for the scenario
TARGET_BUG_ID="4096"
TARGET_COUNT=7

DISTRACTOR_1_ID="1024"
DISTRACTOR_1_COUNT=3

DISTRACTOR_2_ID="2048"
DISTRACTOR_2_COUNT=2

NOISE_COUNT=25

echo "Generating inbox scenario..."
echo "Target: Bug $TARGET_BUG_ID ($TARGET_COUNT msgs)"
echo "Distractor 1: Bug $DISTRACTOR_1_ID ($DISTRACTOR_1_COUNT msgs)"
echo "Distractor 2: Bug $DISTRACTOR_2_ID ($DISTRACTOR_2_COUNT msgs)"

python3 << PYEOF
import os
import glob
import time
import shutil
import random
import email
from email.policy import default

MAILDIR = "$MAILDIR"
ASSETS_HAM = "$ASSETS_HAM"
TARGET_BUG_ID = "$TARGET_BUG_ID"
TARGET_COUNT = int("$TARGET_COUNT")
DISTRACTORS = [
    ("$DISTRACTOR_1_ID", int("$DISTRACTOR_1_COUNT")),
    ("$DISTRACTOR_2_ID", int("$DISTRACTOR_2_COUNT"))
]
NOISE_COUNT = int("$NOISE_COUNT")

# Get list of source emails
src_emails = glob.glob(os.path.join(ASSETS_HAM, "*.eml"))
if not src_emails:
    print("ERROR: No source emails found!")
    exit(1)

def create_email(base_file, bug_id, index, subject_prefix=""):
    with open(base_file, 'rb') as f:
        msg = email.message_from_binary_file(f, policy=default)
    
    # Modify headers to create the scenario
    # Keep original body/sender to maintain realism
    
    original_subject = msg['subject']
    # Strip existing tags if needed, but adding ours is usually enough
    new_subject = f"[Bug {bug_id}] {subject_prefix}Server stability issue report"
    
    del msg['subject']
    msg['subject'] = new_subject
    
    del msg['message-id']
    msg['message-id'] = f"<{time.time()}-{bug_id}-{index}@generated.local>"
    
    # Save to Maildir
    # Format: timestamp.uid.host:2,S (S=Seen)
    filename = f"{int(time.time())}_{bug_id}_{index}.scenario.host:2,S"
    path = os.path.join(MAILDIR, "cur", filename)
    
    with open(path, 'wb') as f:
        f.write(msg.as_bytes())

# 1. Generate Target Thread
base_email = random.choice(src_emails)
for i in range(TARGET_COUNT):
    prefix = "Re: " if i > 0 else ""
    create_email(base_email, TARGET_BUG_ID, i, prefix)

# 2. Generate Distractor Threads
for d_id, d_count in DISTRACTORS:
    base_email = random.choice(src_emails)
    for i in range(d_count):
        prefix = "Re: " if i > 0 else ""
        create_email(base_email, d_id, i, prefix)

# 3. Generate Noise (Unrelated emails)
# Ensure they don't accidentally match our bug IDs
random.shuffle(src_emails)
for i in range(NOISE_COUNT):
    if i >= len(src_emails): break
    
    # Just copy file directly but give unique name
    src = src_emails[i]
    filename = f"{int(time.time())}_noise_{i}.host:2,S"
    dst = os.path.join(MAILDIR, "cur", filename)
    shutil.copy(src, dst)

print("Scenario generation complete.")
PYEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ==============================================================================
# 3. Save Ground Truth
# ==============================================================================

cat > /tmp/task_ground_truth.json << EOF
{
    "target_bug_id": "$TARGET_BUG_ID",
    "target_count": $TARGET_COUNT,
    "distractor_bug_ids": ["$DISTRACTOR_1_ID", "$DISTRACTOR_2_ID"],
    "task_start_time": $(date +%s)
}
EOF

# ==============================================================================
# 4. Final UI Setup
# ==============================================================================

# Maximize BlueMail
maximize_bluemail
sleep 5

# Send F5 or Ctrl+R to ensure inbox refreshes (BlueMail usually syncs auto, but good to force)
# Note: BlueMail doesn't always have a refresh hotkey, but waiting usually works.
sleep 10

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="