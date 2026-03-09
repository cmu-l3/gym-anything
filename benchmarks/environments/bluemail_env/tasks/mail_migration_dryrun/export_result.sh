#!/bin/bash
echo "=== Exporting mail_migration_dryrun result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Paths
MANIFEST_PATH="/home/ga/Documents/migration_manifest.csv"
MAILDIR="/home/ga/Maildir"

# Record file stats
MANIFEST_EXISTS="false"
MANIFEST_SIZE=0
MANIFEST_MTIME=0
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_SIZE=$(stat -c%s "$MANIFEST_PATH" 2>/dev/null || echo "0")
    MANIFEST_MTIME=$(stat -c%Y "$MANIFEST_PATH" 2>/dev/null || echo "0")
fi

# Check BlueMail status
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# Use Python for robust parsing of CSV and Maildir
python3 << 'PYEOF'
import os
import json
import csv
import re
import glob

# Configuration
manifest_path = "/home/ga/Documents/migration_manifest.csv"
maildir_path = "/home/ga/Maildir"
default_folders = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}
initial_inbox_count = 50  # Hardcoded fallback, usually read from /tmp

# Helper to count emails in a Maildir folder (cur + new)
def count_maildir_folder(folder_path):
    count = 0
    for subdir in ['cur', 'new']:
        p = os.path.join(folder_path, subdir)
        if os.path.isdir(p):
            count += len([f for f in os.listdir(p) if os.path.isfile(os.path.join(p, f))])
    return count

# Helper to parse email file headers
def parse_email_headers(fpath):
    headers = {'to': '', 'subject': '', 'body': ''}
    try:
        with open(fpath, 'r', errors='ignore') as f:
            content = f.read(8000)
            
        # simple header parser
        for line in content.split('\n'):
            if not line.strip(): break # End of headers
            if ':' in line:
                key, val = line.split(':', 1)
                k = key.strip().lower()
                if k in ['to', 'subject']:
                    headers[k] = val.strip()
        
        # simple body extract (first few lines after headers)
        parts = content.split('\n\n', 1)
        if len(parts) > 1:
            headers['body'] = parts[1][:500].lower()
            
    except Exception:
        pass
    return headers

# 1. Analyze Manifest
manifest_data = {
    'valid_csv': False,
    'has_header': False,
    'row_count': 0,
    'cols': [],
    'sample_rows': []
}

if os.path.exists(manifest_path):
    try:
        with open(manifest_path, 'r', errors='ignore') as f:
            # Check for empty file
            first_char = f.read(1)
            if not first_char:
                raise ValueError("Empty file")
            f.seek(0)
            
            # Sniff dialect
            sample = f.read(1024)
            f.seek(0)
            sniffer = csv.Sniffer()
            has_header = sniffer.has_header(sample)
            dialect = sniffer.sniff(sample)
            
            reader = csv.reader(f, dialect)
            rows = list(reader)
            
            if len(rows) > 0:
                manifest_data['valid_csv'] = True
                manifest_data['has_header'] = has_header
                manifest_data['row_count'] = len(rows) - (1 if has_header else 0)
                if has_header:
                    manifest_data['cols'] = [c.lower() for c in rows[0]]
                    manifest_data['sample_rows'] = rows[1:4] # Grab a few for validation
                else:
                    manifest_data['sample_rows'] = rows[:3]
    except Exception as e:
        manifest_data['error'] = str(e)

# 2. Analyze Maildir Structure (Custom Folders)
custom_folders = {}
for entry in os.listdir(maildir_path):
    if entry.startswith('.'):
        folder_name = entry[1:] # Remove leading dot
        if folder_name not in default_folders and os.path.isdir(os.path.join(maildir_path, entry)):
            cnt = count_maildir_folder(os.path.join(maildir_path, entry))
            custom_folders[folder_name] = cnt

# 3. Analyze Drafts for Report
drafts_found = []
draft_dir = os.path.join(maildir_path, '.Drafts')
if os.path.isdir(draft_dir):
    for subdir in ['cur', 'new']:
        dpath = os.path.join(draft_dir, subdir)
        if os.path.isdir(dpath):
            for fname in os.listdir(dpath):
                fpath = os.path.join(dpath, fname)
                if os.path.isfile(fpath):
                    drafts_found.append(parse_email_headers(fpath))

# 4. Analyze Inbox Count (Movement check)
current_inbox = count_maildir_folder(os.path.join(maildir_path, 'cur')) + \
                count_maildir_folder(os.path.join(maildir_path, 'new'))

# Compile Result
result = {
    'manifest': manifest_data,
    'custom_folders': custom_folders,
    'custom_folder_count': len(custom_folders),
    'emails_in_custom_folders': sum(custom_folders.values()),
    'current_inbox_count': current_inbox,
    'drafts': drafts_found
}

with open('/tmp/py_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Merge Python analysis with shell vars
cat << EOF > /tmp/task_result.json
{
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_size": $MANIFEST_SIZE,
    "manifest_mtime": $MANIFEST_MTIME,
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)",
    "analysis": $(cat /tmp/py_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json