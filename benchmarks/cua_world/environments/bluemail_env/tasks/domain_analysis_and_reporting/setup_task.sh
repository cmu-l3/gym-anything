#!/bin/bash
# Setup script for domain_analysis_and_reporting task
echo "=== Setting up domain_analysis_and_reporting ==="

source /workspace/scripts/task_utils.sh

# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# DO NOT kill BlueMail -- killing it loses the account config stored in LevelDB.
# DO NOT stop Dovecot -- it may disrupt ongoing IMAP wizard setup.
# Maildir is manipulated directly; doveadm will re-index after changes.

MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear inbox and custom folders
rm -f "${MAILDIR}/cur/"* 2>/dev/null || true
rm -f "${MAILDIR}/new/"* 2>/dev/null || true

for dir in "${MAILDIR}"/.*/; do
    folder_name=$(basename "$dir" | sed 's/^\.//')
    case "$folder_name" in
        Drafts|Sent|Junk|Trash|INBOX) continue ;;
        *) rm -rf "$dir" 2>/dev/null || true ;;
    esac
done

rm -f "${MAILDIR}/.Drafts/cur/"* "${MAILDIR}/.Drafts/new/"* 2>/dev/null || true
rm -f "${MAILDIR}/.Sent/cur/"* "${MAILDIR}/.Sent/new/"* 2>/dev/null || true

# Load all 50 ham emails into inbox
TIMESTAMP=$(date +%s)
IDX=0
HAM_LOADED=0
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    FNAME="${TIMESTAMP}_${IDX}.$(hostname -s):2,S"
    cp "$eml_file" "${MAILDIR}/cur/${FNAME}"
    IDX=$((IDX + 1))
    TIMESTAMP=$((TIMESTAMP + 1))
    HAM_LOADED=$((HAM_LOADED + 1))
done
echo "Loaded ${HAM_LOADED} ham emails"

# Reset subscriptions
cat > "${MAILDIR}/subscriptions" << 'SUBEOF'
Junk
Drafts
Sent
Trash
SUBEOF

chown -R ga:ga "${MAILDIR}"

# Dynamically discover top 3 sender domains for use in verification
python3 << 'PYEOF'
import os, re, json
from collections import Counter

MAILDIR = "/home/ga/Maildir"
domains = []
for fname in os.listdir(f"{MAILDIR}/cur"):
    fpath = os.path.join(MAILDIR, "cur", fname)
    try:
        with open(fpath, 'r', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if line.lower().startswith('from:'):
                    m = re.search(r'@([\w.-]+)', line)
                    if m:
                        domains.append(m.group(1).lower())
                    break
    except Exception:
        pass

counts = Counter(domains)
top3 = [d for d, _ in counts.most_common(3)]
top_domains_data = {
    'top_domains': top3,
    'domain_counts': {d: c for d, c in counts.most_common(10)}
}
with open('/tmp/top_sender_domains.json', 'w') as f:
    json.dump(top_domains_data, f, indent=2)
print(f"Top 3 domains: {top3}")
PYEOF

# Record baseline
INBOX_COUNT=$(ls "${MAILDIR}/cur/" "${MAILDIR}/new/" 2>/dev/null | grep -c . || echo 0)
echo "${INBOX_COUNT}" > /tmp/initial_inbox_count
echo "0" > /tmp/initial_custom_folder_count

date +%s > /tmp/task_start_timestamp

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes

# Ensure BlueMail is running (DO NOT kill -- preserves account config)
if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

# Maximize and wait for BlueMail to sync new Maildir state
maximize_bluemail
sleep 20

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete: domain_analysis_and_reporting (inbox=${INBOX_COUNT}) ==="
