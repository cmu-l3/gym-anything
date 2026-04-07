#!/bin/bash
echo "=== Setting up vendor_invoice_consolidation ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Clean up environment
rm -rf "/home/ga/Documents/Invoices" 2>/dev/null || true
mkdir -p "/home/ga/Documents"

# 2. Inject specific Invoice Emails into Maildir using Python
# We use Python to ensure correct MIME structure for attachments
python3 << 'EOF'
import email
from email.message import EmailMessage
import time
import os
import socket

MAILDIR = "/home/ga/Maildir/cur"
HOSTNAME = socket.gethostname()

def create_invoice_email(sender, subject, filename, content, time_offset):
    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From'] = sender
    msg['To'] = 'ga@example.com'
    msg.set_content(f"Please find attached the invoice {filename}.\n\nRegards,\n{sender.split('<')[0].strip()}")
    
    # Add attachment
    msg.add_attachment(content.encode('utf-8'), maintype='text', subtype='csv', filename=filename)
    
    # Generate unique filename for Maildir
    ts = int(time.time()) - time_offset
    unique_name = f"{ts}.M{ts}P{os.getpid()}Q{time_offset}.{HOSTNAME}:2,S"
    
    with open(os.path.join(MAILDIR, unique_name), 'wb') as f:
        f.write(msg.as_bytes())

# Invoice 1: Acme
create_invoice_email(
    "Acme Corp Accounts <accounts@acmecorp.com>", 
    "Invoice 2024-001 from Acme Corp", 
    "acme_inv.csv", 
    "ID,Item,Cost\n101,Widget A,500.00\n102,Service Fee,150.00",
    3600
)

# Invoice 2: Beta
create_invoice_email(
    "Beta Industries <billing@betaind.com>", 
    "Pending Invoice: Beta Industries", 
    "beta_inv.csv", 
    "Date,Service,Hours,Rate\n2024-01-15,Consulting,5,100",
    7200
)

# Invoice 3: Gamma
create_invoice_email(
    "Gamma LLC <finance@gammallc.com>", 
    "Gamma LLC - Service Invoice", 
    "gamma_inv.csv", 
    "SKU,Description,Qty,Unit_Price\nGM-99,Logistics Support,1,1200.00",
    1800
)

print("Injected 3 invoice emails into Maildir")
EOF

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 4. Start BlueMail
if ! is_bluemail_running; then
    start_bluemail
fi

# Wait for window and maximize
wait_for_bluemail_window 60
maximize_bluemail

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="