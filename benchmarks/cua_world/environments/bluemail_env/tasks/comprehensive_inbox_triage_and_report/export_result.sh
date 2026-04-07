#!/bin/bash
# Export results for comprehensive_inbox_triage_and_report task
# Collects folder state, email data, report file, and outgoing emails.

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

BLUEMAIL_UP="false"
if is_bluemail_running; then
    BLUEMAIL_UP="true"
fi

python3 << 'PYEOF'
import json, os, re, glob, email

MAILDIR = "/home/ga/Maildir"
REPORT_PATH = "/home/ga/Documents/triage_report.txt"
DEFAULT_FOLDERS = {'Drafts', 'Sent', 'Junk', 'Trash', 'INBOX', 'spam', 'ham', 'Archive'}

SECURITY_KEYWORDS = [
    'spam', 'virus', 'klez', 'security', 'encryption', 'encrypt',
    'phishing', 'abuse', 'habeus', 'habeas', 'spamassassin',
    'malware', 'antispam', 'anti-spam', 'satalk', 'sadev'
]

def count_dir(path):
    """Count files in a Maildir cur/ + new/ directory."""
    count = 0
    for sub in ['cur', 'new']:
        d = os.path.join(path, sub)
        if os.path.isdir(d):
            count += len([f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f))])
    return count

def parse_email_file(fpath):
    """Parse an email file and return headers + body snippet."""
    try:
        with open(fpath, 'r', errors='replace') as fh:
            content = fh.read(15000)
        msg = email.message_from_string(content)
        subj = msg.get('Subject', '') or ''
        sender = msg.get('From', '') or ''
        to_addr = msg.get('To', '') or ''
        cc = msg.get('CC', '') or msg.get('Cc', '') or ''
        bcc = msg.get('BCC', '') or msg.get('Bcc', '') or ''

        body = ''
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == 'text/plain':
                    payload = part.get_payload(decode=True)
                    if payload:
                        body = payload.decode('utf-8', errors='replace')[:2000]
                    break
        else:
            payload = msg.get_payload(decode=True)
            if payload:
                body = payload.decode('utf-8', errors='replace')[:2000]

        return {
            'subject': subj,
            'from': sender,
            'to': to_addr.lower(),
            'cc': cc.lower(),
            'bcc': bcc.lower(),
            'body': body.lower()[:2000],
            'filename': os.path.basename(fpath)
        }
    except Exception as e:
        return {'subject': '', 'from': '', 'to': '', 'cc': '', 'bcc': '',
                'body': '', 'filename': os.path.basename(fpath), 'error': str(e)}

def normalize_subject(subj):
    if not subj:
        return ""
    s = subj
    prev = None
    while s != prev:
        prev = s
        s = re.sub(r'^(\s*(Re|RE|re|Fwd|FW|fwd|Fw)\s*:\s*)+', '', s)
        s = re.sub(r'^(\s*\[.*?\]\s*)+', '', s)
    s = s.strip().rstrip('.!?').strip()
    return s.lower()

def scan_folder(folder_path):
    """Scan a Maildir folder and return parsed emails."""
    emails = []
    for sub in ['cur', 'new']:
        d = os.path.join(folder_path, sub)
        if not os.path.isdir(d):
            continue
        for fname in os.listdir(d):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                emails.append(parse_email_file(fpath))
    return emails

# Read task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        TASK_START = float(f.read().strip())
except:
    TASK_START = 0

# Load ground truth for comparison
try:
    with open('/tmp/ground_truth.json', 'r') as f:
        gt = json.load(f)
except:
    gt = {}

# Count inbox
inbox_count = count_dir(MAILDIR)

# Find custom folders
custom_folders = {}
threads_folder_data = None
security_folder_data = None

for entry in os.listdir(MAILDIR):
    if not entry.startswith('.') or not os.path.isdir(os.path.join(MAILDIR, entry)):
        continue
    folder_name = entry[1:]  # strip leading dot
    if folder_name in DEFAULT_FOLDERS:
        continue

    folder_path = os.path.join(MAILDIR, entry)
    folder_count = count_dir(folder_path)
    folder_emails = scan_folder(folder_path)

    custom_folders[folder_name] = {
        'count': folder_count,
        'emails': folder_emails
    }

    # Identify threads folder
    if 'thread' in folder_name.lower() or 'active' in folder_name.lower():
        threads_folder_data = {
            'name': folder_name,
            'count': folder_count,
            'emails': folder_emails
        }

    # Identify security folder
    if 'security' in folder_name.lower() or 'review' in folder_name.lower():
        security_folder_data = {
            'name': folder_name,
            'count': folder_count,
            'emails': folder_emails
        }

# Check thread accuracy against ground truth
thread_tp = 0
thread_fp = 0
if threads_folder_data and gt.get('threads'):
    gt_thread_subjects = set()
    for norm_subj in gt['threads']:
        gt_thread_subjects.add(norm_subj)
    for em in threads_folder_data.get('emails', []):
        norm = normalize_subject(em.get('subject', ''))
        if norm in gt_thread_subjects:
            thread_tp += 1
        else:
            thread_fp += 1

# Check security accuracy
sec_tp = 0
sec_fp = 0
if security_folder_data:
    for em in security_folder_data.get('emails', []):
        subj_lower = em.get('subject', '').lower()
        if any(kw in subj_lower for kw in SECURITY_KEYWORDS):
            sec_tp += 1
        else:
            sec_fp += 1

# Check report file
report_data = {
    'exists': False,
    'content': '',
    'size': 0,
    'created_during_task': False
}
if os.path.isfile(REPORT_PATH):
    report_data['exists'] = True
    stat = os.stat(REPORT_PATH)
    report_data['size'] = stat.st_size
    report_data['created_during_task'] = stat.st_mtime > TASK_START
    try:
        with open(REPORT_PATH, 'r', errors='replace') as f:
            report_data['content'] = f.read()[:5000]
    except:
        pass

# Parse outgoing emails (Drafts + Sent)
outgoing = []
for folder in ['.Drafts', '.Sent']:
    folder_path = os.path.join(MAILDIR, folder)
    for sub in ['cur', 'new']:
        d = os.path.join(folder_path, sub)
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d)):
            fpath = os.path.join(d, fname)
            if os.path.isfile(fpath):
                parsed = parse_email_file(fpath)
                parsed['folder'] = folder[1:]  # strip dot
                outgoing.append(parsed)

# Build result
result = {
    'inbox_count': inbox_count,
    'threads_folder': {
        'exists': threads_folder_data is not None,
        'name': threads_folder_data['name'] if threads_folder_data else None,
        'count': threads_folder_data['count'] if threads_folder_data else 0,
        'true_positives': thread_tp,
        'false_positives': thread_fp
    },
    'security_folder': {
        'exists': security_folder_data is not None,
        'name': security_folder_data['name'] if security_folder_data else None,
        'count': security_folder_data['count'] if security_folder_data else 0,
        'true_positives': sec_tp,
        'false_positives': sec_fp
    },
    'custom_folders': {k: {'count': v['count']} for k, v in custom_folders.items()},
    'report': report_data,
    'outgoing_emails': outgoing,
    'ground_truth_summary': {
        'total_thread_emails': gt.get('total_thread_emails', 0),
        'thread_count': len(gt.get('threads', {})),
        'security_count': gt.get('security_emails', {}).get('count', 0),
        'expected_remaining': gt.get('expected_remaining', 0)
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export complete: inbox={inbox_count}, "
      f"threads_folder={'exists' if threads_folder_data else 'missing'}, "
      f"security_folder={'exists' if security_folder_data else 'missing'}, "
      f"report={'exists' if report_data['exists'] else 'missing'}, "
      f"outgoing={len(outgoing)}")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null

# Patch bluemail_running into JSON
if command -v jq &>/dev/null; then
    jq --arg up "$BLUEMAIL_UP" '. + {bluemail_running: ($up == "true")}' \
        /tmp/task_result.json > /tmp/task_result_tmp.json && \
        mv /tmp/task_result_tmp.json /tmp/task_result.json
    chmod 666 /tmp/task_result.json 2>/dev/null
fi

echo "Export result written to /tmp/task_result.json"
