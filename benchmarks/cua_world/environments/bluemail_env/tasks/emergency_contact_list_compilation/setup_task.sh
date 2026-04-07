#!/bin/bash
echo "=== Setting up Emergency Contact List Compilation ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure BlueMail is running
# ============================================================
# Restart Dovecot to ensure mail serving is active
systemctl restart dovecot 2>/dev/null || dovecot 2>/dev/null || true

# Start BlueMail if needed
if ! is_bluemail_running; then
    start_bluemail
fi

# ============================================================
# 2. Inject Solvable Data (Phone Numbers)
# ============================================================
# To ensure the task is solvable and verifiable, we will inject
# specific phone numbers into the signatures of 5 random emails
# in the inbox. This ensures "Ground Truth" exists.

MAILDIR="/home/ga/Maildir"
INBOX_DIR="$MAILDIR/cur"

# Define 5 fake identities to inject
declare -a NAMES=("Sarah Jenkins" "Marcus Thorne" "Elena Rodriguez" "David Chen" "Fiona O'Malley")
declare -a TITLES=("Operations Lead" "SysAdmin" "Logistics Coordinator" "Network Engineer" "Facility Manager")
declare -a PHONES=("555-0123" "555-0199" "555-0145" "555-0178" "555-0112")

echo "Injecting target data into inbox..."

# Get list of email files
FILES=($(ls "$INBOX_DIR" | sort -R | head -n 5))

for i in {0..4}; do
    if [ -f "$INBOX_DIR/${FILES[$i]}" ]; then
        # Append signature to the email body
        # We use >> to append. Since these are simple text/plain emails (mostly) 
        # or raw .eml files, appending to the end usually works for visualization 
        # in simple clients, though MIME boundaries can be tricky.
        # BlueMail handles raw text appends reasonably well for rendering if simple.
        
        # A safer way for MIME messages is to insert before the last boundary, 
        # but for this environment's corpus (often simple text), appending usually works 
        # enough to be visible, or we just rely on the text being in the file.
        
        # We'll simply append text. BlueMail's viewer is robust.
        echo "" >> "$INBOX_DIR/${FILES[$i]}"
        echo "" >> "$INBOX_DIR/${FILES[$i]}"
        echo "-- " >> "$INBOX_DIR/${FILES[$i]}"
        echo "${NAMES[$i]}" >> "$INBOX_DIR/${FILES[$i]}"
        echo "${TITLES[$i]}" >> "$INBOX_DIR/${FILES[$i]}"
        echo "Phone: ${PHONES[$i]}" >> "$INBOX_DIR/${FILES[$i]}"
        echo "Internal Ext: 10${i}" >> "$INBOX_DIR/${FILES[$i]}"
        
        echo "Injected ${NAMES[$i]} (${PHONES[$i]}) into ${FILES[$i]}"
    fi
done

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# Wait for BlueMail window
wait_for_bluemail_window 60

# Maximize
maximize_bluemail

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="