#!/bin/bash
echo "=== Setting up legal_hold_preservation task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. CLEANUP & PREPARATION
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"
ASSETS_SPAM="/workspace/assets/emails/spam"

# Clear existing mail
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Junk/cur/"* "${MAILDIR}/.Junk/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -rf "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Remove custom folders
for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

# ============================================================
# 2. LOAD DATA (50 Ham, 20 Spam)
# ============================================================
echo "Loading emails..."
TIMESTAMP=$(date +%s)
IDX=0

# Load 50 Ham into Inbox
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 50 ] && break
    # Unique name ensuring no collisions
    cp "$eml_file" "${MAILDIR}/cur/${TIMESTAMP}_${IDX}.ham.ga:2,S"
    IDX=$((IDX + 1))
done

# Load 20 Spam into Junk
SPAM_IDX=0
for eml_file in "${ASSETS_SPAM}"/spam_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $SPAM_IDX -ge 20 ] && break
    cp "$eml_file" "${MAILDIR}/.Junk/cur/${TIMESTAMP}_${SPAM_IDX}.spam.ga:2,S"
    SPAM_IDX=$((SPAM_IDX + 1))
done

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 3. CALCULATE GROUND TRUTH (HIDDEN FROM AGENT)
# ============================================================
# We scan the loaded files to identify which ones contain the keywords.
# This establishes the "Perfect Agent" baseline.

python3 << 'PYEOF'
import os
import re
import json

keywords = ["license", "copyright", "patent", "GPL"]
maildir = "/home/ga/Maildir"
truth = {
    "total_matches": 0,
    "inbox_matches": 0,
    "junk_matches": 0,
    "matching_files": []
}

def check_file(path, source_folder):
    try:
        with open(path, 'r', errors='ignore') as f:
            content = f.read().lower()
        
        # Check if ANY keyword is present
        is_match = any(k.lower() in content for k in keywords)
        
        if is_match:
            truth["total_matches"] += 1
            if source_folder == "Inbox":
                truth["inbox_matches"] += 1
            else:
                truth["junk_matches"] += 1
            
            truth["matching_files"].append({
                "path": path,
                "folder": source_folder,
                "filename": os.path.basename(path)
            })
    except Exception as e:
        pass

# Scan Inbox
inbox_dir = os.path.join(maildir, "cur")
if os.path.exists(inbox_dir):
    for f in os.listdir(inbox_dir):
        check_file(os.path.join(inbox_dir, f), "Inbox")

# Scan Junk
junk_dir = os.path.join(maildir, ".Junk/cur")
if os.path.exists(junk_dir):
    for f in os.listdir(junk_dir):
        check_file(os.path.join(junk_dir, f), "Junk")

with open("/tmp/ground_truth_matches.json", "w") as f:
    json.dump(truth, f, indent=2)

print(f"Ground Truth Calculated: {truth['total_matches']} matches ({truth['inbox_matches']} Inbox, {truth['junk_matches']} Junk)")
PYEOF

# ============================================================
# 4. APP LAUNCH
# ============================================================
date +%s > /tmp/task_start_time.txt

if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="