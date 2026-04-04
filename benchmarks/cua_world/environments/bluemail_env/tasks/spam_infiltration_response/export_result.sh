#!/bin/bash
# Export script for spam_infiltration_response task
echo "=== Exporting spam_infiltration_response result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

INITIAL_JUNK=$(cat /tmp/initial_junk_count 2>/dev/null || echo "10")
INITIAL_INBOX=$(cat /tmp/initial_inbox_count 2>/dev/null || echo "50")

python3 << 'PYEOF'
import os, json, re

MAILDIR = "/home/ga/Maildir"
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}

def count_dir(path):
    if not os.path.isdir(path):
        return 0
    return len([f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))])

def parse_email(fpath):
    try:
        with open(fpath, 'r', errors='ignore') as f:
            content = f.read(8000)
        headers = {}
        lines = content.split('\n')
        in_body = False
        body_lines = []
        for line in lines:
            if in_body:
                body_lines.append(line)
                if len(body_lines) >= 30:
                    break
                continue
            if line.strip() == '' and not in_body:
                in_body = True
                continue
            m = re.match(r'^([\w-]+):\s*(.*)', line)
            if m:
                key = m.group(1).lower()
                if key not in headers:
                    headers[key] = m.group(2).strip()
        return {
            'to': headers.get('to', ''),
            'subject': headers.get('subject', ''),
            'cc': headers.get('cc', ''),
            'bcc': headers.get('bcc', ''),
            'body': ' '.join(body_lines[:20]).lower()
        }
    except Exception:
        return {'to': '', 'subject': '', 'cc': '', 'bcc': '', 'body': ''}

inbox_count = count_dir(f"{MAILDIR}/cur") + count_dir(f"{MAILDIR}/new")
junk_count = count_dir(f"{MAILDIR}/.Junk/cur") + count_dir(f"{MAILDIR}/.Junk/new")

# Find Spam-Incidents folder specifically
spam_incidents_count = 0
spam_incidents_path = f"{MAILDIR}/.Spam-Incidents"
if os.path.isdir(spam_incidents_path):
    spam_incidents_count = count_dir(f"{spam_incidents_path}/cur") + count_dir(f"{spam_incidents_path}/new")

custom_folders = {}
for entry in os.listdir(MAILDIR):
    if not entry.startswith('.'):
        continue
    folder_name = entry[1:]
    if folder_name in DEFAULT_FOLDERS:
        continue
    folder_path = os.path.join(MAILDIR, entry)
    if not os.path.isdir(folder_path):
        continue
    count = count_dir(f"{folder_path}/cur") + count_dir(f"{folder_path}/new")
    custom_folders[folder_name] = count

drafts = []
for subdir in ['cur', 'new']:
    dpath = f"{MAILDIR}/.Drafts/{subdir}"
    if os.path.isdir(dpath):
        for fname in os.listdir(dpath):
            fpath = os.path.join(dpath, fname)
            if os.path.isfile(fpath):
                drafts.append(parse_email(fpath))

sent = []
for subdir in ['cur', 'new']:
    spath = f"{MAILDIR}/.Sent/{subdir}"
    if os.path.isdir(spath):
        files = sorted(os.listdir(spath))[-5:]
        for fname in files:
            fpath = os.path.join(spath, fname)
            if os.path.isfile(fpath):
                sent.append(parse_email(fpath))

initial_junk = int(open('/tmp/initial_junk_count').read().strip()) if os.path.exists('/tmp/initial_junk_count') else 10
initial_inbox = int(open('/tmp/initial_inbox_count').read().strip()) if os.path.exists('/tmp/initial_inbox_count') else 50

result = {
    'inbox_count': inbox_count,
    'junk_count': junk_count,
    'initial_junk_count': initial_junk,
    'initial_inbox_count': initial_inbox,
    'junk_increase': junk_count - initial_junk,
    'spam_incidents_folder_exists': os.path.isdir(f"{MAILDIR}/.Spam-Incidents"),
    'spam_incidents_count': spam_incidents_count,
    'custom_folders': custom_folders,
    'custom_folder_count': len(custom_folders),
    'drafts': drafts,
    'sent': sent,
    'draft_count': len(drafts)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export: inbox={inbox_count}, junk={junk_count} (was {initial_junk}, +{junk_count - initial_junk}), spam_incidents={spam_incidents_count}, drafts={len(drafts)}")
PYEOF

if [ ! -f /tmp/task_result.json ]; then
    echo '{"inbox_count": 50, "junk_count": 10, "initial_junk_count": 10, "junk_increase": 0, "spam_incidents_folder_exists": false, "spam_incidents_count": 0, "custom_folder_count": 0, "custom_folders": {}, "drafts": [], "sent": [], "draft_count": 0}' > /tmp/task_result.json
fi

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
