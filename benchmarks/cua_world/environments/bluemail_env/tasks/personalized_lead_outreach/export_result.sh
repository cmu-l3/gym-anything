#!/bin/bash
echo "=== Exporting personalized_lead_outreach results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
MAILDIR="/home/ga/Maildir"
CSV_PATH="/home/ga/Documents/candidates.csv"
CANDIDATES_FOLDER="${MAILDIR}/.Candidates"

# Python script to parse email files and CSV
python3 << 'PYEOF'
import os
import csv
import json
import email
from email.header import decode_header

def decode_str(s):
    if not s: return ""
    decoded_list = decode_header(s)
    result = ""
    for b, enc in decoded_list:
        if isinstance(b, bytes):
            try:
                result += b.decode(enc or 'utf-8', errors='ignore')
            except:
                result += b.decode('utf-8', errors='ignore')
        else:
            result += str(b)
    return result

def parse_eml(fpath):
    try:
        with open(fpath, 'rb') as f:
            msg = email.message_from_binary_file(f)
        
        subject = decode_str(msg.get('Subject', ''))
        from_header = decode_str(msg.get('From', ''))
        to_header = decode_str(msg.get('To', ''))
        
        # Extract body (simple text extraction)
        body = ""
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    try:
                        body += part.get_payload(decode=True).decode('utf-8', errors='ignore')
                    except:
                        pass
        else:
            try:
                body = msg.get_payload(decode=True).decode('utf-8', errors='ignore')
            except:
                pass
                
        # Parse name/email from "From" header
        # Example: "John Doe <john@example.com>"
        import email.utils
        realname, email_addr = email.utils.parseaddr(from_header)
        
        return {
            "subject": subject,
            "from": from_header,
            "from_name": realname,
            "from_email": email_addr,
            "to": to_header,
            "body": body
        }
    except Exception as e:
        return {"error": str(e)}

# 1. Read CSV
csv_data = []
csv_exists = os.path.exists("/home/ga/Documents/candidates.csv")
if csv_exists:
    try:
        with open("/home/ga/Documents/candidates.csv", 'r') as f:
            reader = csv.DictReader(f)
            # Normalize headers to lowercase for verification
            reader.fieldnames = [x.lower() for x in reader.fieldnames] if reader.fieldnames else []
            for row in reader:
                csv_data.append(row)
    except Exception as e:
        print(f"CSV Error: {e}")

# 2. Read Candidates Folder Emails
candidates_emails = []
cand_dir_cur = os.path.join("/home/ga/Maildir/.Candidates", "cur")
cand_dir_new = os.path.join("/home/ga/Maildir/.Candidates", "new")

for d in [cand_dir_cur, cand_dir_new]:
    if os.path.exists(d):
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                parsed = parse_eml(fpath)
                candidates_emails.append(parsed)

# 3. Read Sent Emails
sent_emails = []
sent_dir_cur = os.path.join("/home/ga/Maildir/.Sent", "cur")
sent_dir_new = os.path.join("/home/ga/Maildir/.Sent", "new")

for d in [sent_dir_cur, sent_dir_new]:
    if os.path.exists(d):
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                parsed = parse_eml(fpath)
                sent_emails.append(parsed)

# Output JSON
result = {
    "csv_exists": csv_exists,
    "csv_data": csv_data,
    "candidates_folder_exists": os.path.exists("/home/ga/Maildir/.Candidates"),
    "candidates_emails": candidates_emails,
    "sent_emails": sent_emails,
    "task_start_ts": int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0,
    "csv_mtime": os.path.getmtime("/home/ga/Documents/candidates.csv") if csv_exists else 0
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="