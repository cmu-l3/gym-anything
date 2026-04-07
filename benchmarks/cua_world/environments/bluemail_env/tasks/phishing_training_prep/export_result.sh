#!/bin/bash
# Export script for phishing_training_prep task
echo "=== Exporting phishing_training_prep result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check if BlueMail is running
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Run Python script to analyze Maildir state and extract email content
python3 << 'PYEOF'
import os
import json
import re
import glob

MAILDIR = "/home/ga/Maildir"
TASK_START_FILE = "/tmp/task_start_timestamp"

def get_email_content(filepath):
    """Simple parser to get headers and partial body"""
    try:
        with open(filepath, 'r', errors='ignore') as f:
            content = f.read()
            
        headers = {}
        body = ""
        
        # Split headers and body
        parts = content.split('\n\n', 1)
        header_block = parts[0]
        body_block = parts[1] if len(parts) > 1 else ""
        
        # Parse headers
        current_key = None
        for line in header_block.split('\n'):
            if re.match(r'^\s', line) and current_key:
                headers[current_key] += " " + line.strip()
            else:
                match = re.match(r'^([\w-]+):\s*(.*)', line)
                if match:
                    current_key = match.group(1).lower()
                    headers[current_key] = match.group(2).strip()
        
        return {
            'subject': headers.get('subject', ''),
            'to': headers.get('to', ''),
            'from': headers.get('from', ''),
            'body': body_block[:5000]  # First 5000 chars
        }
    except Exception as e:
        return {'error': str(e)}

def find_training_folder():
    """Find the training folder case-insensitively"""
    for entry in os.listdir(MAILDIR):
        if not entry.startswith('.'): continue
        folder_name = entry[1:]
        if folder_name.lower().replace('_', '').replace('-', '') == 'trainingexamples':
            return folder_name, os.path.join(MAILDIR, entry)
    return None, None

def analyze_maildir():
    result = {
        'training_folder_found': False,
        'training_folder_name': None,
        'training_email_count': 0,
        'training_emails': [],
        'drafts': [],
        'sent': [],
        'junk_count': 0
    }
    
    # Check Training Folder
    fname, fpath = find_training_folder()
    if fname and fpath:
        result['training_folder_found'] = True
        result['training_folder_name'] = fname
        
        # Count and analyze emails in folder
        emails = []
        for subdir in ['cur', 'new']:
            p = os.path.join(fpath, subdir)
            if os.path.isdir(p):
                for f in os.listdir(p):
                    full_path = os.path.join(p, f)
                    if os.path.isfile(full_path):
                        content = get_email_content(full_path)
                        emails.append({
                            'subject': content.get('subject', ''),
                            'from': content.get('from', '')
                        })
        result['training_email_count'] = len(emails)
        result['training_emails'] = emails
        
    # Check Drafts/Sent for the announcement
    for folder in ['.Drafts', '.Sent']:
        target_list = result['drafts'] if folder == '.Drafts' else result['sent']
        base_path = os.path.join(MAILDIR, folder)
        for subdir in ['cur', 'new']:
            p = os.path.join(base_path, subdir)
            if os.path.isdir(p):
                for f in os.listdir(p):
                    full_path = os.path.join(p, f)
                    if os.path.isfile(full_path):
                        # Only include files modified after task start
                        try:
                            mtime = os.path.getmtime(full_path)
                            start_time = 0
                            if os.path.exists(TASK_START_FILE):
                                with open(TASK_START_FILE, 'r') as tf:
                                    start_time = int(tf.read().strip())
                            
                            if mtime > start_time:
                                content = get_email_content(full_path)
                                target_list.append(content)
                        except:
                            pass

    # Check Junk count
    junk_count = 0
    junk_path = os.path.join(MAILDIR, '.Junk')
    for subdir in ['cur', 'new']:
        p = os.path.join(junk_path, subdir)
        if os.path.isdir(p):
            junk_count += len([name for name in os.listdir(p) if os.path.isfile(os.path.join(p, name))])
    result['junk_count'] = junk_count

    return result

# Execute analysis
data = analyze_maildir()
data['bluemail_running'] = os.environ.get('BM_RUNNING', 'false') == 'true'

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="