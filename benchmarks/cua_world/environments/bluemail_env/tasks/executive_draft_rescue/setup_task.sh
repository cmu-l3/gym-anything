#!/bin/bash
set -e
echo "=== Setting up executive_draft_rescue ==="

# Source utilities
source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Clear previous state (Sent, Drafts, Trash)
MAILDIR="/home/ga/Maildir"
rm -f "$MAILDIR/.Drafts/cur/"* "$MAILDIR/.Drafts/new/"* 2>/dev/null || true
rm -f "$MAILDIR/.Sent/cur/"* "$MAILDIR/.Sent/new/"* 2>/dev/null || true
rm -f "$MAILDIR/.Trash/cur/"* "$MAILDIR/.Trash/new/"* 2>/dev/null || true

# 3. Inject Drafts into Maildir
# We inject directly into the file system. Dovecot/BlueMail will pick these up.
DRAFTS_DIR="$MAILDIR/.Drafts/cur"
mkdir -p "$DRAFTS_DIR"

# Timestamp base
TS=$(date +%s)

# Draft 1: The Proposal (To be edited and sent)
cat > "$DRAFTS_DIR/${TS}_1.proposal:2,DS" <<EOF
From: ga@example.com
To: client.relations@strategic-partners.com
Subject: Q3 Strategic Proposal - Draft
Message-ID: <proposal-draft-${TS}@example.com>
Date: $(date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Hi Sarah,

Per our discussion yesterday, here is the
EOF

# Draft 2: The Stale Lunch Draft (To be deleted)
cat > "$DRAFTS_DIR/${TS}_2.lunch:2,DS" <<EOF
From: ga@example.com
To: lunch-club@internal.team
Subject: Taco Tuesday?
Message-ID: <lunch-draft-${TS}@example.com>
Date: $(date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Are we going to that place on 4th street again?
EOF

# Draft 3: The Invoice Query (To be kept)
cat > "$DRAFTS_DIR/${TS}_3.invoice:2,DS" <<EOF
From: ga@example.com
To: vendor-billing@suppliers.net
Subject: Invoice #9928 Query
Message-ID: <invoice-draft-${TS}@example.com>
Date: $(date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Please hold off on payment. I need to verify the line items.
EOF

# Fix permissions
chown -R ga:ga "$MAILDIR"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# 5. Ensure BlueMail is running
if ! is_bluemail_running; then
    start_bluemail
fi

# 6. Wait for window and maximize
wait_for_bluemail_window 60
sleep 5
maximize_bluemail

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete: 3 Drafts injected ==="