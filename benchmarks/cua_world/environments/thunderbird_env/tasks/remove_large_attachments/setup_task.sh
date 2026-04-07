#!/bin/bash
echo "=== Setting up remove_large_attachments task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

echo "Stopping Thunderbird if running..."
close_thunderbird
sleep 2

PROFILE_DIR="/home/ga/.thunderbird/default-release"
INBOX_FILE="${PROFILE_DIR}/Mail/Local Folders/Inbox"
MSF_FILE="${PROFILE_DIR}/Mail/Local Folders/Inbox.msf"

# Remove index to force rebuild
rm -f "$MSF_FILE"

echo "Injecting target large emails..."
python3 -c "
import email
from email.message import EmailMessage
import time
import os

inbox_path = '/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox'
os.makedirs(os.path.dirname(inbox_path), exist_ok=True)

def append_to_mbox(subject, filename, content_type, file_data):
    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From'] = 'attorney@lawfirm.example.com'
    msg['To'] = 'ga@example.com'
    msg['Date'] = email.utils.formatdate(localtime=True)
    msg.set_content('Please find attached the ' + filename + ' for your review.')
    
    maintype, subtype = content_type.split('/')
    msg.add_attachment(file_data, maintype=maintype, subtype=subtype, filename=filename)
    
    with open(inbox_path, 'a') as f:
        f.write('From attorney@lawfirm.example.com ' + time.ctime() + '\n')
        f.write(msg.as_string())
        f.write('\n\n')

# Create realistic-sized dummy files
pdf_data = b'%PDF-1.4\n' + b'1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n' + b'A' * 2000000
append_to_mbox('Case Evidence: Smith vs Jones (Deposition)', 'deposition.pdf', 'application/pdf', pdf_data)

img_data = b'BM' + b'\x00' * 1500000
append_to_mbox('Case Evidence: Exhibit B Scans', 'exhibit_b.bmp', 'image/bmp', img_data)

csv_data = b'id,name,value\n' + b'1,test,100\n' * 100000
append_to_mbox('Case Evidence: Financial Disclosures', 'financials.csv', 'text/csv', csv_data)
"

# Fix permissions
chown -R ga:ga "$PROFILE_DIR"

echo "Starting Thunderbird..."
start_thunderbird
wait_for_thunderbird_window 30
sleep 5
maximize_thunderbird

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="