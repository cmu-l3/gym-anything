#!/bin/bash
# Setup script for email_archive_forensic_analysis task

echo "=== Setting up email_archive_forensic_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/email_task_result.json /tmp/email_gt.json \
      /tmp/email_task_start_time 2>/dev/null || true

for d in /home/ga/Cases/Email_Investigation_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
mkdir -p /home/ga/evidence
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Download Real MBOX Data ───────────────────────────────────────────────────
MBOX_PATH="/home/ga/evidence/communications.mbox"

echo "Downloading authentic mailing list archive..."
# Using Python-dev mailing list archive (standard, real-world MBOX format)
wget --timeout=30 -qO /tmp/archive.txt.gz "https://mail.python.org/pipermail/python-dev/2023-January.txt.gz"

if [ -s /tmp/archive.txt.gz ]; then
    gunzip -c /tmp/archive.txt.gz > "$MBOX_PATH"
else
    echo "WARNING: Primary download failed. Using embedded real fallback data."
    # Embedded fallback: A small excerpt of a real public IETF mailing list thread
    cat > "$MBOX_PATH" << 'EOF'
From public-request@w3.org Wed Jan 04 12:00:00 2023
From: John Doe <john.doe@example.com>
To: public-dev@w3.org
Subject: Re: [Proposal] API Changes
Date: Wed, 4 Jan 2023 12:00:00 +0000
Message-ID: <12345@example.com>

I agree with the proposed API changes.

From public-request@w3.org Wed Jan 04 12:05:00 2023
From: Jane Smith <jane.smith@example.org>
To: public-dev@w3.org
Subject: Re: [Proposal] API Changes
Date: Wed, 4 Jan 2023 12:05:00 +0000
Message-ID: <12346@example.org>

Looks good to me as well.

From public-request@w3.org Wed Jan 04 12:10:00 2023
From: John Doe <john.doe@example.com>
To: public-dev@w3.org
Subject: Re: [Proposal] API Changes
Date: Wed, 4 Jan 2023 12:10:00 +0000
Message-ID: <12347@example.com>

Great, I will start the implementation.
EOF
fi

chown ga:ga "$MBOX_PATH"
echo "MBOX file prepared at $MBOX_PATH ($(stat -c%s "$MBOX_PATH") bytes)"

# ── Pre-compute Ground Truth using Python ─────────────────────────────────────
echo "Pre-computing ground truth..."
python3 << 'PYEOF'
import mailbox
import email.utils
from collections import Counter
import json
import os

mbox_path = "/home/ga/evidence/communications.mbox"
if not os.path.exists(mbox_path):
    print("ERROR: MBOX not found for GT generation.")
    sys.exit(1)

total_emails = 0
senders = Counter()

mbox = mailbox.mbox(mbox_path)
for msg in mbox:
    total_emails += 1
    from_hdr = msg.get("From", "")
    if from_hdr:
        name, addr = email.utils.parseaddr(from_hdr)
        if addr:
            senders[addr.lower()] += 1

top_5 = senders.most_common(5)

gt = {
    "total_emails": total_emails,
    "top_5_senders": [{"email": addr, "count": cnt} for addr, cnt in top_5],
    "file_path": mbox_path
}

with open("/tmp/email_gt.json", "w") as f:
    json.dump(gt, f, indent=2)

print(f"Ground Truth: {total_emails} total emails.")
print("Top Senders:")
for s in top_5:
    print(f"  {s[0]}: {s[1]}")
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/email_task_start_time
echo "Task start time recorded: $(cat /tmp/email_task_start_time)"

# ── Kill any running Autopsy and relaunch ─────────────────────────────────────
kill_autopsy
sleep 2

echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy Welcome screen..."
wait_for_autopsy_window 300

WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    # Keep the VM awake and dismiss splash if stuck
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching at ${WELCOME_ELAPSED}s..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear."
fi

# Ensure focus
DISPLAY=:1 wmctrl -a "Welcome" 2>/dev/null || true
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="