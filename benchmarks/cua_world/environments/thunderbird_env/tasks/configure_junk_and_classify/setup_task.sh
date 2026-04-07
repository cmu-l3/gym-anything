#!/bin/bash
echo "=== Setting up configure_junk_and_classify task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed so we can modify files safely
close_thunderbird
sleep 2

PROFILE_DIR="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="${PROFILE_DIR}/Mail/Local Folders"
INBOX_MBOX="${LOCAL_MAIL_DIR}/Inbox"
JUNK_MBOX="${LOCAL_MAIL_DIR}/Junk"
PREFS_FILE="${PROFILE_DIR}/prefs.js"

mkdir -p "$LOCAL_MAIL_DIR"
touch "$INBOX_MBOX"
touch "$JUNK_MBOX"

# ============================================================
# Disable junk mail controls (agent must enable them)
# ============================================================
if [ -f "$PREFS_FILE" ]; then
    # Remove any existing junk prefs
    sed -i '/mail\.server\.server1\.spamLevel/d' "$PREFS_FILE"
    sed -i '/mail\.server\.server1\.moveOnSpam/d' "$PREFS_FILE"
    sed -i '/mail\.server\.server1\.moveTargetMode/d' "$PREFS_FILE"
    
    # Explicitly disable them to set starting state
    echo 'user_pref("mail.server.server1.spamLevel", 0);' >> "$PREFS_FILE"
    echo 'user_pref("mail.server.server1.moveOnSpam", false);' >> "$PREFS_FILE"
fi

# ============================================================
# Inject 5 spam emails into Inbox
# ============================================================
SPAM_DIR="/workspace/assets/emails/spam"
SPAM_SUBJECTS_FILE="/home/ga/Desktop/spam_subjects.txt"
SPAM_SUBJECTS_INTERNAL="/tmp/spam_subjects.txt"

# Ensure Desktop exists
mkdir -p /home/ga/Desktop
> "$SPAM_SUBJECTS_FILE"
> "$SPAM_SUBJECTS_INTERNAL"

INJECTED=0
if [ -d "$SPAM_DIR" ]; then
    # Get spam files, skip the first 20 to avoid duplicates if other tasks ran
    SPAM_FILES=($(ls "$SPAM_DIR"/ 2>/dev/null | sort))
    TOTAL_SPAM=${#SPAM_FILES[@]}
    
    START_IDX=20
    if [ $TOTAL_SPAM -le 25 ]; then
        START_IDX=$((TOTAL_SPAM - 5))
        [ $START_IDX -lt 0 ] && START_IDX=0
    fi
    
    for i in $(seq $START_IDX $((START_IDX + 4))); do
        if [ $i -lt $TOTAL_SPAM ]; then
            SPAM_FILE="${SPAM_DIR}/${SPAM_FILES[$i]}"
            if [ -f "$SPAM_FILE" ]; then
                # Extract subject and clean it
                SUBJECT=$(grep -m1 "^Subject:" "$SPAM_FILE" 2>/dev/null | sed 's/^Subject:\s*//' | head -1 | tr -d '\r')
                if [ -z "$SUBJECT" ]; then
                    SUBJECT="(no subject - spam file ${SPAM_FILES[$i]})"
                fi
                
                # Extract sender for mbox From line
                SENDER=$(grep -m1 "^From:" "$SPAM_FILE" 2>/dev/null | sed 's/From: //' | head -1 | tr -d '\r' || echo "spammer@example.com")
                DATE=$(grep -m1 "^Date:" "$SPAM_FILE" 2>/dev/null | sed 's/Date: //' | head -1 | tr -d '\r' || echo "$(date -R)")
                
                # Append to Inbox in mbox format
                echo "From ${SENDER} ${DATE}" >> "$INBOX_MBOX"
                cat "$SPAM_FILE" >> "$INBOX_MBOX"
                echo "" >> "$INBOX_MBOX"
                
                # Record subject for verifier and agent
                echo "$SUBJECT" >> "$SPAM_SUBJECTS_FILE"
                echo "$SUBJECT" >> "$SPAM_SUBJECTS_INTERNAL"
                
                INJECTED=$((INJECTED + 1))
            fi
        fi
    done
fi

echo "Injected $INJECTED spam emails into Inbox."

# Remove stale .msf index files so Thunderbird rebuilds them properly
rm -f "${LOCAL_MAIL_DIR}/"*.msf 2>/dev/null || true

# Set proper ownership
chown -R ga:ga /home/ga/.thunderbird
chown ga:ga "$SPAM_SUBJECTS_FILE"

# Record initial email counts
INITIAL_INBOX=$(count_emails_in_mbox "$INBOX_MBOX")
INITIAL_JUNK=$(count_emails_in_mbox "$JUNK_MBOX")
echo "$INITIAL_INBOX" > /tmp/initial_inbox_count.txt
echo "$INITIAL_JUNK" > /tmp/initial_junk_count.txt

# ============================================================
# Start Thunderbird
# ============================================================
start_thunderbird
sleep 5

# Wait for window and maximize
if wait_for_thunderbird_window 30; then
    maximize_thunderbird
    sleep 2
fi

# Dismiss any potential startup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="