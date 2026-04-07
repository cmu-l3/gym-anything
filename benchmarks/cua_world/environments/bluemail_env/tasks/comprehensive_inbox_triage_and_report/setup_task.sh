#!/bin/bash
# Setup for comprehensive_inbox_triage_and_report task
# Loads 50 ham emails as unread into Inbox, computes ground truth
# for thread groupings and security-related emails.

source /workspace/scripts/task_utils.sh

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# ── 1. Close BlueMail (preserve LevelDB account config) ──
close_bluemail

# ── 2. Clear all Maildir folders ──
rm -f "${MAILDIR}"/cur/* "${MAILDIR}"/new/* 2>/dev/null
rm -f "${MAILDIR}"/.Drafts/cur/* "${MAILDIR}"/.Drafts/new/* 2>/dev/null
rm -f "${MAILDIR}"/.Sent/cur/* "${MAILDIR}"/.Sent/new/* 2>/dev/null
rm -f "${MAILDIR}"/.Junk/cur/* "${MAILDIR}"/.Junk/new/* 2>/dev/null
rm -f "${MAILDIR}"/.Trash/cur/* "${MAILDIR}"/.Trash/new/* 2>/dev/null

# Remove all custom folders (keep only standard ones)
find "${MAILDIR}" -maxdepth 1 -type d -name '.*' \
    ! -name '.Drafts' ! -name '.Sent' ! -name '.Junk' ! -name '.Trash' \
    -exec rm -rf {} + 2>/dev/null || true

# Ensure standard dirs exist
for d in cur new tmp; do
    mkdir -p "${MAILDIR}/${d}"
    mkdir -p "${MAILDIR}/.Drafts/${d}"
    mkdir -p "${MAILDIR}/.Sent/${d}"
    mkdir -p "${MAILDIR}/.Junk/${d}"
    mkdir -p "${MAILDIR}/.Trash/${d}"
done

# ── 3. Load all 50 ham emails as UNREAD into Inbox ──
# BlueMail's default IMAP sync window is 2 weeks. The SpamAssassin corpus
# emails are from 2002, far outside any sync window. We update Date headers
# to recent timestamps so they appear in BlueMail regardless of sync settings.
# Email content, subjects, senders, and threading remain unchanged.
TIMESTAMP=$(date +%s)
IDX=0
python3 << 'LOAD_PYEOF'
import glob, os, re, time

ASSETS = "/workspace/assets/emails/ham"
MAILDIR_CUR = "/home/ga/Maildir/cur"
base_ts = int(time.time())

files = sorted(glob.glob(os.path.join(ASSETS, "ham_*.eml")))
for idx, fpath in enumerate(files, 1):
    ts = base_ts + idx
    with open(fpath, 'r', errors='replace') as f:
        content = f.read()

    # Replace the Date header with a recent timestamp (stagger by 1 minute each)
    from email.utils import formatdate
    new_date = formatdate(ts - (len(files) - idx) * 60, localtime=False, usegmt=True)
    content = re.sub(r'^Date:.*$', f'Date: {new_date}', content, count=1, flags=re.MULTILINE)

    dest = os.path.join(MAILDIR_CUR, f"{ts}_ham{idx}.ga:2,")
    with open(dest, 'w') as f:
        f.write(content)

print(f"Loaded {len(files)} ham emails into Inbox")
LOAD_PYEOF
IDX=$(ls "${MAILDIR}/cur/" | wc -l)

# ── 4. Fix permissions ──
chown -R ga:ga "${MAILDIR}"
chmod -R 700 "${MAILDIR}"

# ── 5. Write subscriptions ──
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF
chown ga:ga "${MAILDIR}/subscriptions"

# ── 6. Reset Dovecot indexes ──
reset_dovecot_indexes

# ── 6b. Clear BlueMail's IMAP sync cache ──
# After Maildir repopulation + Dovecot index reset, BlueMail's IndexedDB
# holds stale IMAP UIDs causing sync mismatch ("No messages").
# Clearing the IndexedDB forces a fresh IMAP sync on next start.
# Account config in Local Storage is preserved.
rm -rf /home/ga/.config/BlueMail/IndexedDB 2>/dev/null
rm -rf /home/ga/.config/BlueMail/Cache 2>/dev/null
rm -rf /home/ga/.config/BlueMail/blob_storage 2>/dev/null
rm -rf /home/ga/.config/BlueMail/GPUCache 2>/dev/null
rm -rf "/home/ga/.config/BlueMail/Session Storage" 2>/dev/null

# ── 7. Delete stale output files BEFORE recording timestamp ──
rm -f /home/ga/Documents/triage_report.txt
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# ── 8. Record task start time ──
date +%s > /tmp/task_start_time.txt

# ── 9. Compute ground truth ──
python3 << 'PYEOF'
import email, json, os, re, glob
from collections import defaultdict

def normalize_subject(subj):
    """Strip reply/forward prefixes, list tags, trailing punctuation.
    Iterates until stable to handle nested [List] Re: [List] Re: patterns."""
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

# Subject-only keywords to avoid false positives from body content.
# Includes 'satalk'/'sadev' to catch SpamAssassin mailing list emails.
SECURITY_KEYWORDS = [
    'spam', 'virus', 'klez', 'security', 'encryption', 'encrypt',
    'phishing', 'abuse', 'habeus', 'habeas', 'spamassassin',
    'malware', 'antispam', 'anti-spam', 'satalk', 'sadev'
]

maildir_cur = '/home/ga/Maildir/cur'
emails_data = []

for fpath in sorted(glob.glob(os.path.join(maildir_cur, '*'))):
    fname = os.path.basename(fpath)
    with open(fpath, 'r', errors='replace') as fh:
        msg = email.message_from_file(fh)

    subj = msg.get('Subject', '') or ''
    sender = msg.get('From', '') or ''
    norm = normalize_subject(subj)

    # Check subject only for security keywords (avoids false positives
    # from body content where words like 'threat' or 'filter' appear
    # in non-security contexts)
    subj_lower = subj.lower()
    is_security = any(kw in subj_lower for kw in SECURITY_KEYWORDS)

    emails_data.append({
        'filename': fname,
        'subject': subj,
        'normalized_subject': norm,
        'sender': sender,
        'is_security': is_security
    })

# Group by normalized subject
thread_groups = defaultdict(list)
for e in emails_data:
    thread_groups[e['normalized_subject']].append(e)

# Threads with 3+ messages
threads_3plus = {}
thread_filenames = set()
for norm_subj, members in thread_groups.items():
    if len(members) >= 3:
        threads_3plus[norm_subj] = {
            'count': len(members),
            'subjects': [m['subject'] for m in members],
            'senders': list(set(m['sender'] for m in members)),
            'filenames': [m['filename'] for m in members]
        }
        for m in members:
            thread_filenames.add(m['filename'])

# Security emails NOT already in 3+ threads
security_emails = [
    e for e in emails_data
    if e['is_security'] and e['filename'] not in thread_filenames
]

ground_truth = {
    'total_emails': len(emails_data),
    'threads': threads_3plus,
    'total_thread_emails': len(thread_filenames),
    'thread_filenames': sorted(thread_filenames),
    'security_emails': {
        'count': len(security_emails),
        'subjects': [e['subject'] for e in security_emails],
        'filenames': [e['filename'] for e in security_emails]
    },
    'expected_remaining': len(emails_data) - len(thread_filenames) - len(security_emails)
}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

os.chmod('/tmp/ground_truth.json', 0o600)
os.chown('/tmp/ground_truth.json', 0, 0)

print(f"Ground truth: {len(threads_3plus)} threads ({len(thread_filenames)} emails), "
      f"{len(security_emails)} security emails, "
      f"{ground_truth['expected_remaining']} remaining")
PYEOF

# ── 10. Start BlueMail and wait for sync ──
if ! is_bluemail_running; then
    start_bluemail
fi
wait_for_bluemail_window 60
maximize_bluemail
sleep 10

# ── 11. Take initial screenshot ──
take_screenshot /tmp/task_initial.png

echo "Setup complete for comprehensive_inbox_triage_and_report"
