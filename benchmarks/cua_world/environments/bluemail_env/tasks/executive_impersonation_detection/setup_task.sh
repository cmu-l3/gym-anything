#!/bin/bash
set -e
echo "=== Setting up executive_impersonation_detection task ==="

source /workspace/scripts/task_utils.sh
# Stop BlueMail before modifying Maildir to avoid stale IMAP cache
close_bluemail

# ============================================================
# 1. Clean Slate Setup
# ============================================================
MAILDIR="/home/ga/Maildir"
ASSETS_HAM="/workspace/assets/emails/ham"

# Clear existing mail to ensure clean state
rm -rf "${MAILDIR}/cur/"* "${MAILDIR}/new/"* 2>/dev/null || true
# Remove custom folders
find "${MAILDIR}" -maxdepth 1 -type d -name ".*" ! -name "." ! -name ".." ! -name ".Junk" ! -name ".Trash" ! -name ".Drafts" ! -name ".Sent" -exec rm -rf {} +

# Re-create standard folders if missing
mkdir -p "${MAILDIR}/cur" "${MAILDIR}/new" "${MAILDIR}/tmp"
mkdir -p "${MAILDIR}/.Drafts/cur" "${MAILDIR}/.Drafts/new"
mkdir -p "${MAILDIR}/.Sent/cur" "${MAILDIR}/.Sent/new"

# ============================================================
# 2. Inject Background Noise (Real Ham)
# ============================================================
echo "Injecting background emails..."
TIMESTAMP=$(date +%s)
IDX=0
# Load ~40 real ham emails for noise
for eml_file in "${ASSETS_HAM}"/ham_*.eml; do
    [ -f "$eml_file" ] || continue
    [ $IDX -ge 40 ] && break
    
    # Copy with unique name
    cp "$eml_file" "${MAILDIR}/cur/${TIMESTAMP}_noise_${IDX}.host:2,S"
    IDX=$((IDX + 1))
done

# ============================================================
# 3. Inject Scenario Emails (Real vs Fake CTO)
# ============================================================
echo "Injecting BEC scenario emails..."

# Helper to generate EML content
create_eml() {
    local track_id=$1
    local from_addr=$2
    local subject=$3
    local body=$4
    local date_offset=$5
    
    local date_str=$(date -R -d "-$date_offset minutes")
    
    cat <<EOF > "${MAILDIR}/cur/${TIMESTAMP}_${track_id}.host:2,S"
Return-Path: <$from_addr>
X-Original-To: ga@example.com
Delivered-To: ga@example.com
From: "Justin Mason" <$from_addr>
To: ga@example.com
Subject: $subject
Date: $date_str
Message-Id: <${TIMESTAMP}.${track_id}@mail.example.com>
X-BEC-Track: $track_id
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii

$body
EOF
}

# Real Email 1
create_eml "bec_real_01" "jm@jmason.org" "Re: SA 2.40 release details" \
    "Thanks for the update. The release candidate looks stable on my end. Let's proceed with the rollout schedule as discussed in the engineering sync." \
    120

# Real Email 2
create_eml "bec_real_02" "jm@jmason.org" "Patch for ruleset" \
    "I noticed a regression in the latest ruleset update. Attached is the patch to fix the false positives we saw yesterday. Please merge." \
    300

# Fake Email 1 (Gmail Spoof)
create_eml "bec_fake_01" "ceo.private77@gmail.com" "Urgent: Wire Transfer Request" \
    "I'm in a meeting right now and can't talk, but I need you to process a wire transfer for a vendor immediately. It's time-sensitive for the acquisition. Reply here and I will send the wiring instructions. - Justin" \
    15

# Fake Email 2 (Look-alike Domain)
create_eml "bec_fake_02" "justin.mason@executive-secure.net" "Confidential Acquisition" \
    "Confidential: We are closing a deal with a new partner. I need you to purchase 10 x $100 gift cards for the client team as a gesture of goodwill before 5 PM today. Keep this discreet." \
    45

# Fake Email 3 (Generic Admin Spoof)
create_eml "bec_fake_03" "admin@corp-support-portal.io" "Quick favor needed" \
    "Are you available? I need you to handle a quick payment for me. My corporate card is being declined and this vendor is waiting. I will reimburse you tomorrow." \
    60

# Fix permissions
chown -R ga:ga "${MAILDIR}"

# Reset Dovecot indexes (forces new UIDVALIDITY so BlueMail re-syncs)
reset_dovecot_indexes
# ============================================================
# 4. App Setup
# ============================================================
echo "Starting BlueMail..."
date +%s > /tmp/task_start_time

if ! is_bluemail_running; then
    start_bluemail
    wait_for_bluemail_window 60
fi

maximize_bluemail
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="