#!/bin/bash
echo "=== Exporting community_question_triage result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python analysis script to generate structured result
# We do this in Python to reliably parse headers and filenames
python3 << 'PYEOF'
import os
import json
import re
import email
from email import policy

MAILDIR = "/home/ga/Maildir"
RESULT_FILE = "/tmp/task_result.json"

def parse_maildir_file(filepath):
    """Parse email subject and check flags from filename."""
    filename = os.path.basename(filepath)
    
    # Check flags in filename (Dovecot/Maildir standard)
    # Format: unique_id:2,FLAGS
    # F = Flagged (Starred), S = Seen, T = Trashed, D = Draft, R = Replied
    flags = ""
    if ":2," in filename:
        flags = filename.split(":2,")[1]
    
    is_flagged = 'F' in flags
    
    subject = ""
    try:
        with open(filepath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
            subject = msg.get('subject', '')
            # Decode subject if needed (policy.default handles most, but being safe)
            subject = str(subject).strip()
    except Exception as e:
        print(f"Error parsing {filepath}: {e}")
        
    return {
        'subject': subject,
        'is_flagged': is_flagged,
        'filename': filename
    }

def scan_folder(folder_path):
    """Return list of email data dicts for a folder."""
    emails = []
    # Check both 'cur' and 'new' subdirectories
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path):
            continue
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if os.path.isfile(fpath):
                emails.append(parse_maildir_file(fpath))
    return emails

def check_sent_report():
    """Check for the status report in Sent items."""
    sent_path = os.path.join(MAILDIR, ".Sent")
    if not os.path.exists(sent_path):
        return False
        
    emails = scan_folder(sent_path)
    # Sort by time (heuristic: filename timestamp) to get latest
    emails.sort(key=lambda x: x['filename'], reverse=True)
    
    for em in emails:
        # We can't easily parse 'To' without opening file again, 
        # but verifier logic can be simple here or we expand parse_maildir_file.
        # Let's expand parse to get 'To' for Sent items.
        pass # implemented in main loop if needed
    return len(emails) > 0 # Simplified check

# ---------------------------------------------------------
# Main Analysis
# ---------------------------------------------------------

results = {
    'folders_created': {},
    'inbox_count': 0,
    'community_replies_emails': [],
    'new_topics_emails': [],
    'sent_emails': []
}

# 1. Check Inbox
results['inbox_count'] = len(scan_folder(os.path.join(MAILDIR))) # Root is INBOX

# 2. Check Custom Folders
replies_path = os.path.join(MAILDIR, ".Community-Replies")
topics_path = os.path.join(MAILDIR, ".New-Topics")

results['folders_created']['Community-Replies'] = os.path.isdir(replies_path)
results['folders_created']['New-Topics'] = os.path.isdir(topics_path)

if os.path.isdir(replies_path):
    results['community_replies_emails'] = scan_folder(replies_path)

if os.path.isdir(topics_path):
    results['new_topics_emails'] = scan_folder(topics_path)

# 3. Check Sent
sent_path = os.path.join(MAILDIR, ".Sent")
if os.path.isdir(sent_path):
    # We need to parse 'To' header for sent emails
    for subdir in ['cur', 'new']:
        path = os.path.join(sent_path, subdir)
        if os.path.exists(path):
            for fname in os.listdir(path):
                fpath = os.path.join(path, fname)
                try:
                    with open(fpath, 'rb') as f:
                        msg = email.message_from_binary_file(f, policy=policy.default)
                        results['sent_emails'].append({
                            'to': str(msg.get('to', '')),
                            'subject': str(msg.get('subject', '')),
                            'body': str(msg.get_body(preferencelist=('plain')).get_content()) if msg.get_body(preferencelist=('plain')) else ""
                        })
                except:
                    pass

# Save to JSON
with open(RESULT_FILE, 'w') as f:
    json.dump(results, f, indent=2)

print(f"Exported results to {RESULT_FILE}")
PYEOF

# Move result to final location with permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="