#!/bin/bash
echo "=== Exporting conversation_thread_consolidation result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Verify BlueMail state
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# 3. Analyze Maildir Structure and Content using Python
# We use Python for robust subject parsing and coherence checking
python3 << 'PYEOF'
import os
import json
import re
import email
from email.header import decode_header

MAILDIR = "/home/ga/Maildir"
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}

def decode_subject(header_value):
    if not header_value:
        return ""
    decoded_fragments = decode_header(header_value)
    subject = ""
    for fragment, charset in decoded_fragments:
        if isinstance(fragment, bytes):
            try:
                subject += fragment.decode(charset or 'utf-8', errors='ignore')
            except:
                subject += fragment.decode('utf-8', errors='ignore')
        else:
            subject += str(fragment)
    return subject

def normalize_subject(subject):
    """Strip Re:, Fwd:, [ListTags], and whitespace to find base subject."""
    s = subject.lower()
    # Remove Re:, Fwd:, etc. (recursive to handle Re: Re: ...)
    s = re.sub(r'^\s*(?:re|fwd|fw|aw|antw):\s*', '', s)
    s = re.sub(r'^\s*(?:re|fwd|fw|aw|antw):\s*', '', s) 
    # Remove list tags like [SAdev] or [123]
    s = re.sub(r'\[.*?\]', '', s)
    # Remove special chars and extra spaces
    s = re.sub(r'[^\w\s]', '', s)
    return s.strip()

def check_coherence(subjects):
    """
    Check if a list of subjects is 'coherent' (forms a thread).
    Returns True if >= 60% of subjects share a common base topic.
    """
    if len(subjects) < 2:
        return False
        
    normalized = [normalize_subject(s) for s in subjects if s]
    if len(normalized) < 2:
        return False

    # Simple heuristic: compare every pair. If a subject is similar to any other, it's 'threaded'.
    # If the majority of emails in the folder are 'threaded', the folder is coherent.
    threaded_count = 0
    for i, s1 in enumerate(normalized):
        is_connected = False
        for j, s2 in enumerate(normalized):
            if i == j: continue
            # Check for substantial overlap (substring or Levenshtein-ish match)
            # We use a simplified common substring check for length > 5
            if len(s1) > 5 and len(s2) > 5:
                if s1 in s2 or s2 in s1:
                    is_connected = True
                    break
        if is_connected:
            threaded_count += 1
            
    ratio = threaded_count / len(normalized)
    return ratio >= 0.6

def parse_folder(folder_path):
    emails = []
    subjects = []
    
    for subdir in ['cur', 'new']:
        path = os.path.join(folder_path, subdir)
        if not os.path.exists(path):
            continue
            
        for fname in os.listdir(path):
            fpath = os.path.join(path, fname)
            if os.path.isfile(fpath):
                try:
                    with open(fpath, 'rb') as f:
                        msg = email.message_from_binary_file(f)
                        subj = decode_subject(msg.get('Subject', ''))
                        subjects.append(subj)
                        
                        # Store basic info for report checking
                        emails.append({
                            'to': decode_subject(msg.get('To', '')),
                            'subject': subj,
                            'body': str(msg.get_payload())[:500] # Truncate body
                        })
                except Exception as e:
                    print(f"Error parsing {fname}: {e}")
                    
    return emails, subjects

# --- Main Analysis ---

# 1. Analyze Custom Folders
custom_folders_data = {}
coherent_folders_count = 0

for entry in os.listdir(MAILDIR):
    if not entry.startswith('.'): continue
    folder_name = entry[1:] # Strip leading dot
    if folder_name in DEFAULT_FOLDERS: continue
    
    folder_path = os.path.join(MAILDIR, entry)
    if not os.path.isdir(folder_path): continue
    
    folder_emails, folder_subjects = parse_folder(folder_path)
    count = len(folder_emails)
    
    if count > 0:
        is_coherent = check_coherence(folder_subjects)
        if is_coherent and count >= 2:
            coherent_folders_count += 1
            
        custom_folders_data[folder_name] = {
            'count': count,
            'coherent': is_coherent,
            'subjects_sample': folder_subjects[:3]
        }

# 2. Analyze Inbox
inbox_emails, _ = parse_folder(MAILDIR) # Maildir root is Inbox
inbox_count = len(inbox_emails)

# 3. Analyze Drafts and Sent (for report)
drafts, _ = parse_folder(os.path.join(MAILDIR, '.Drafts'))
sent, _ = parse_folder(os.path.join(MAILDIR, '.Sent'))

# 4. Get Initial Data
try:
    with open('/tmp/initial_inbox_count', 'r') as f:
        initial_inbox = int(f.read().strip())
except:
    initial_inbox = 50

try:
    with open('/tmp/task_start_time', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# 5. Construct Result
result = {
    'task_start': task_start,
    'task_end': int(os.popen('date +%s').read().strip()),
    'app_was_running': True, # Passed from bash check outside if needed
    'initial_inbox_count': initial_inbox,
    'final_inbox_count': inbox_count,
    'inbox_reduction': initial_inbox - inbox_count,
    'custom_folders': custom_folders_data,
    'custom_folder_count': len(custom_folders_data),
    'coherent_folders_count': coherent_folders_count,
    'drafts': drafts,
    'sent': sent,
    'screenshot_path': "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Update app_running status in the JSON (since python script hardcoded it)
# We do a quick sed patch or just rely on python
if [ "$APP_RUNNING" = "false" ]; then
    sed -i 's/"app_was_running": true/"app_was_running": false/' /tmp/task_result.json
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="