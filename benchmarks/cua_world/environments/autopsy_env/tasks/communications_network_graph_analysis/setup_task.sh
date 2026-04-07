#!/bin/bash
# Setup script for communications_network_graph_analysis task

echo "=== Setting up communications_network_graph_analysis task ==="

source /workspace/scripts/task_utils.sh

# ── Clean up stale artifacts ──────────────────────────────────────────────────
rm -f /tmp/network_analysis_result.json /tmp/network_analysis_gt.json \
      /tmp/network_analysis_start_time 2>/dev/null || true

for d in /home/ga/Cases/Network_Analysis_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

mkdir -p /home/ga/Reports
mkdir -p /home/ga/evidence
chown -R ga:ga /home/ga/Reports/ 2>/dev/null || true

# ── Prepare MBOX Evidence File ────────────────────────────────────────────────
MBOX_FILE="/home/ga/evidence/corporate_emails.mbox"
rm -f "$MBOX_FILE"

echo "Downloading real W3C mailing list archive..."
wget -q -O /tmp/archive.txt.gz --timeout=30 "https://lists.w3.org/Archives/Public/public-html/2014Jan.txt.gz"

if [ -s /tmp/archive.txt.gz ]; then
    echo "W3C Archive downloaded successfully. Decompressing..."
    gunzip -c /tmp/archive.txt.gz > "$MBOX_FILE"
    rm -f /tmp/archive.txt.gz
else
    echo "WARNING: Download failed. Generating a realistic corporate email archive fallback..."
    python3 << 'PYEOF'
import mailbox
import email.message
import random
from datetime import datetime, timedelta

users = ["ceo@megacorp.com", "cfo@megacorp.com", "cto@megacorp.com", 
         "alice.smith@megacorp.com", "bob.jones@megacorp.com", 
         "charlie.davis@megacorp.com", "diana.prince@megacorp.com", 
         "evan.wright@megacorp.com", "external.vendor@partner.com"]

mbox = mailbox.mbox('/home/ga/evidence/corporate_emails.mbox')

start_date = datetime(2023, 1, 1)
# Create ~350 messages to establish a strong network graph
for i in range(350):
    msg = email.message.EmailMessage()
    msg['Subject'] = f"Corporate Strategy Update {i}"
    
    # CEO is the absolute hub (involved in ~70% of messages)
    # Alice is a secondary hub (involved in ~40%)
    rand_val = random.random()
    if rand_val < 0.5:
        sender = "ceo@megacorp.com"
        recipients = random.sample(users[1:], random.randint(1, 5))
    elif rand_val < 0.8:
        sender = "alice.smith@megacorp.com"
        recipients = ["ceo@megacorp.com"] + random.sample(users[4:], random.randint(1, 3))
    else:
        sender = random.choice(users[1:])
        recipients = ["ceo@megacorp.com", "alice.smith@megacorp.com"]
        
    # Occasionally CC someone
    if random.random() < 0.3:
        msg['Cc'] = random.choice(users)
        
    msg['From'] = sender
    msg['To'] = ", ".join(set(recipients))
    msg['Date'] = (start_date + timedelta(days=i/5.0)).strftime("%a, %d %b %Y %H:%M:%S +0000")
    msg.set_content(f"Message content for thread {i}. Please review the attached corporate strategy documents.")
    mbox.add(msg)
    
mbox.close()
PYEOF
fi

chown ga:ga "$MBOX_FILE"
echo "Evidence MBOX created: $(stat -c%s "$MBOX_FILE") bytes"

# ── Pre-compute Ground Truth using Python's mailbox module ────────────────────
echo "Pre-computing network analysis ground truth..."
python3 << 'PYEOF'
import mailbox
import re
import json
from collections import Counter

MBOX_FILE = "/home/ga/evidence/corporate_emails.mbox"
email_msg_counts = {}  # Tracks distinct messages each email is involved in
total_emails = 0

try:
    mbox = mailbox.mbox(MBOX_FILE)
    total_emails = len(mbox)
    
    for i, msg in enumerate(mbox):
        # Gather all headers that might contain email addresses
        headers = str(msg.get('From', '')) + " " + str(msg.get('To', '')) + " " + str(msg.get('Cc', ''))
        
        # Extract emails safely
        found_emails = re.findall(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', headers)
        
        # Normalize and deduplicate per message
        unique_emails_in_msg = set(e.lower() for e in found_emails)
        
        for e in unique_emails_in_msg:
            if e not in email_msg_counts:
                email_msg_counts[e] = set()
            email_msg_counts[e].add(i)

    # Sort by number of distinct messages the user is associated with
    sorted_communicators = sorted([(e, len(msg_indices)) for e, msg_indices in email_msg_counts.items()], 
                                  key=lambda x: x[1], reverse=True)
    
    gt = {
        "total_emails": total_emails,
        "top_communicators": [{"email": e, "count": c} for e, c in sorted_communicators[:15]]
    }
    
    with open("/tmp/network_analysis_gt.json", "w") as f:
        json.dump(gt, f, indent=2)
        
    print(f"Ground truth computed: {total_emails} total emails.")
    print("Top 3 communicators:")
    for i in range(min(3, len(sorted_communicators))):
        print(f"  {i+1}. {sorted_communicators[i][0]} ({sorted_communicators[i][1]} msgs)")

except Exception as e:
    print(f"ERROR computing ground truth: {e}")
    # Write empty GT so verifier handles it gracefully
    with open("/tmp/network_analysis_gt.json", "w") as f:
        json.dump({"total_emails": 0, "top_communicators": []}, f)
PYEOF

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/network_analysis_start_time
echo "Task start time recorded: $(cat /tmp/network_analysis_start_time)"

# ── Kill any running Autopsy and Launch ───────────────────────────────────────
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy
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
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Autopsy Welcome screen did NOT appear within ${WELCOME_TIMEOUT}s"
    exit 1
fi

sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="