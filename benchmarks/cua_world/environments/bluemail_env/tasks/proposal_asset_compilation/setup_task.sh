#!/bin/bash
set -e
echo "=== Setting up proposal_asset_compilation task ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Maildir structure exists
MAILDIR="/home/ga/Maildir"
mkdir -p "$MAILDIR/cur" "$MAILDIR/new" "$MAILDIR/tmp"
mkdir -p "$MAILDIR/.Sent/cur" "$MAILDIR/.Sent/new" "$MAILDIR/.Sent/tmp"

# Ensure Documents folder exists and is clean of target
mkdir -p /home/ga/Documents
rm -rf /home/ga/Documents/Falcon_Assets

# ------------------------------------------------------------------
# Generate Synthetic Emails with Attachments
# ------------------------------------------------------------------
echo "Generating Project Falcon emails..."

python3 << 'PYEOF'
import email.message
import email.policy
import time
import os
import hashlib
import json

MAILDIR = "/home/ga/Maildir"
HOSTNAME = os.uname().nodename

def create_email_with_attachment(sender, subject, body, filename, content):
    m = email.message.EmailMessage(policy=email.policy.default)
    m['To'] = 'ga@example.com'
    m['From'] = sender
    m['Subject'] = subject
    m['Date'] = email.utils.formatdate(time.time(), usegmt=True)
    m.set_content(body)
    
    # Add attachment
    m.add_attachment(content.encode('utf-8'), filename=filename, 
                     maintype='application', subtype='octet-stream')
    
    # Save to Maildir/new
    timestamp = str(time.time())
    # Unique name format for Maildir
    unique_name = f"{timestamp}_{filename}_{HOSTNAME}"
    path = os.path.join(MAILDIR, "new", unique_name)
    
    with open(path, 'wb') as f:
        f.write(m.as_bytes())
    
    # Calculate hash for verification
    return hashlib.md5(content.encode('utf-8')).hexdigest()

# Define assets
assets = {
    "specs.txt": {
        "sender": "engineering@internal.corp",
        "subject": "Project Falcon: Technical Specs",
        "body": "Hi, attached are the technical specifications for the Falcon bid. - Eng",
        "content": "SPECIFICATIONS v1.0\n1. Latency < 20ms\n2. Throughput > 1GB/s\n3. Uptime 99.99%"
    },
    "budget.csv": {
        "sender": "finance@internal.corp",
        "subject": "Project Falcon: Budget Draft",
        "body": "Attached is the preliminary budget. Please review before submission.",
        "content": "Item,Cost,Quantity\nServer,5000,10\nLicense,200,50\nLabor,150,100"
    },
    "nda.pdf": {
        "sender": "legal@internal.corp",
        "subject": "Project Falcon: Signed NDA",
        "body": "Here is the countersigned NDA. Do not share externally.",
        # Mock PDF content (text based for simplicity but mimicking binary)
        "content": "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\nTRAILER\n<</Root 1 0 R>>\n%%EOF"
    }
}

expected_hashes = {}

# Create the emails
for filename, data in assets.items():
    md5 = create_email_with_attachment(
        data['sender'], 
        data['subject'], 
        data['body'], 
        filename, 
        data['content']
    )
    expected_hashes[filename] = md5
    print(f"Created email for {filename} with hash {md5}")

# Save expected hashes for export_result.sh to use later
with open('/tmp/expected_asset_hashes.json', 'w') as f:
    json.dump(expected_hashes, f)

PYEOF

# Fix permissions
chown -R ga:ga "$MAILDIR"
chown ga:ga /tmp/expected_asset_hashes.json

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# ------------------------------------------------------------------
# Application Setup
# ------------------------------------------------------------------

# Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window
wait_for_bluemail_window 60

# Maximize
maximize_bluemail

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="