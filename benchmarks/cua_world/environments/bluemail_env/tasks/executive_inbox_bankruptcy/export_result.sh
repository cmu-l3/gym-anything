#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Python Script to Analyze Maildir State
# We use Python to parse dates reliably and count flags
python3 << 'PYEOF'
import os
import json
import email
import email.policy
import re
from datetime import datetime

MAILDIR = "/home/ga/Maildir"
ARCHIVE_FOLDER_NAME = "Archive-Backlog"  # Expected name, but we'll search loosely

def parse_email_date(filepath):
    """Extract date object from email file."""
    try:
        with open(filepath, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=email.policy.default)
            if msg['date']:
                dt = email.utils.parsedate_to_datetime(msg['date'])
                if dt: return dt.timestamp()
    except Exception as e:
        pass
    # Fallback to file mtime if header parsing fails (though setup_task ensured headers exist)
    return os.path.getmtime(filepath)

def get_emails_in_folder(folder_path):
    """Return list of dicts {filename, path, timestamp, is_flagged}."""
    emails = []
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path): continue
        for fname in os.listdir(path):
            if fname.startswith('.'): continue
            fpath = os.path.join(path, fname)
            
            # Check for Flagged ('F' or 'S' check? Task says Flag/Star. In Maildir 'F' is Flagged)
            # Dovecot maps IMAP \Flagged to 'F' in suffix (e.g., :2,SF)
            is_flagged = 'F' in fname.split(':')[-1]
            
            emails.append({
                'filename': fname,
                'path': fpath,
                'timestamp': parse_email_date(fpath),
                'is_flagged': is_flagged
            })
    return emails

def parse_sent_emails():
    """Find emails sent to assistant@company.com."""
    sent_emails = []
    sent_dirs = [os.path.join(MAILDIR, '.Sent', d) for d in ['cur', 'new']]
    
    for d in sent_dirs:
        if not os.path.exists(d): continue
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            try:
                with open(fpath, 'rb') as f:
                    msg = email.message_from_binary_file(f, policy=email.policy.default)
                    if msg['to'] and 'assistant@company.com' in msg['to']:
                        # Extract body text
                        body = ""
                        if msg.is_multipart():
                            for part in msg.walk():
                                if part.get_content_type() == "text/plain":
                                    body += part.get_content()
                        else:
                            body = msg.get_content()
                            
                        sent_emails.append({
                            'subject': msg['subject'],
                            'body': body,
                            'to': msg['to']
                        })
            except Exception:
                continue
    return sent_emails

# --- Analyze Inbox ---
inbox_emails = get_emails_in_folder(MAILDIR)
inbox_count = len(inbox_emails)
inbox_flagged_count = sum(1 for e in inbox_emails if e['is_flagged'])
# Get timestamps of inbox emails
inbox_timestamps = [e['timestamp'] for e in inbox_emails]
min_inbox_ts = min(inbox_timestamps) if inbox_timestamps else 0

# --- Analyze Archive Folder ---
# Find folder matching 'Archive-Backlog' (case insensitive search)
archive_path = None
archive_emails = []
found_folder_name = ""

for item in os.listdir(MAILDIR):
    if item.startswith('.') and item != '.':
        # Maildir folders start with dot
        folder_name = item[1:]
        if folder_name.lower() == "archive-backlog":
            archive_path = os.path.join(MAILDIR, item)
            found_folder_name = folder_name
            break

if archive_path:
    archive_emails = get_emails_in_folder(archive_path)

archive_count = len(archive_emails)
archive_timestamps = [e['timestamp'] for e in archive_emails]
max_archive_ts = max(archive_timestamps) if archive_timestamps else 0

# --- Analyze Sent Mail ---
sent_reports = parse_sent_emails()

# --- Construct Result ---
result = {
    "inbox_count": inbox_count,
    "inbox_flagged_count": inbox_flagged_count,
    "archive_folder_found": bool(archive_path),
    "archive_folder_name": found_folder_name,
    "archive_count": archive_count,
    "min_inbox_timestamp": min_inbox_ts,
    "max_archive_timestamp": max_archive_ts,
    "sent_reports": sent_reports,
    "timestamp_check_passed": (min_inbox_ts >= max_archive_ts) if (inbox_count > 0 and archive_count > 0) else False
}

# Save to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
PYEOF

# Move result to readable location
rm -f /tmp/executive_inbox_bankruptcy_result.json 2>/dev/null || true
mv /tmp/task_result.json /tmp/executive_inbox_bankruptcy_result.json
chmod 666 /tmp/executive_inbox_bankruptcy_result.json

echo "Result exported to /tmp/executive_inbox_bankruptcy_result.json"
cat /tmp/executive_inbox_bankruptcy_result.json