#!/bin/bash
set -e

echo "=== Setting up import_eml_files task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Prepare the real .eml files from the environment's existing SpamAssassin ham corpus
EML_DIR="/home/ga/Documents/OldEmails"
CORPUS_DIR="/workspace/assets/emails/ham"

# Clean up any previous state
rm -rf "$EML_DIR"
mkdir -p "$EML_DIR"

LOCAL_MAIL_DIR="/home/ga/.thunderbird/default-release/Mail/Local Folders"
rm -f "${LOCAL_MAIL_DIR}/Client Correspondence"
rm -f "${LOCAL_MAIL_DIR}/Client Correspondence.msf"

echo "Extracting real emails for import task..."
EXPECTED_SUBJECTS_FILE="/tmp/expected_eml_subjects.txt"
> "$EXPECTED_SUBJECTS_FILE"

COUNT=0
if [ -d "$CORPUS_DIR" ]; then
    # Grab 7 real emails
    for eml_file in "$CORPUS_DIR"/*; do
        if [ -f "$eml_file" ] && [ $COUNT -lt 7 ]; then
            # Format filename nicely
            DEST_FILE="$EML_DIR/client_email_0${COUNT}.eml"
            cp "$eml_file" "$DEST_FILE"
            
            # Extract subject for verification (handling possible carriage returns)
            grep -m1 -i "^Subject:" "$DEST_FILE" | sed 's/^Subject:\s*//i' | tr -d '\r' >> "$EXPECTED_SUBJECTS_FILE"
            
            COUNT=$((COUNT + 1))
        fi
    done
fi

# Fallback: if we couldn't find the corpus, extract from the Inbox mbox using Python
if [ $COUNT -lt 7 ]; then
    echo "Using fallback extraction from Inbox..."
    su - ga -c "python3 -c '
import mailbox, os, re
inbox_path = \"/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox\"
eml_dir = \"/home/ga/Documents/OldEmails\"
subjects_file = \"/tmp/expected_eml_subjects.txt\"

if os.path.exists(inbox_path):
    mbox = mailbox.mbox(inbox_path)
    count = 0
    with open(subjects_file, \"w\") as sf:
        for msg in mbox:
            if count >= 7: break
            subj = msg.get(\"Subject\", \"\").replace(\"\\n\", \"\").replace(\"\\r\", \"\")
            if subj.strip():
                with open(os.path.join(eml_dir, f\"client_email_{count:02d}.eml\"), \"wb\") as f:
                    f.write(msg.as_bytes())
                sf.write(subj + \"\\n\")
                count += 1
'"
fi

# Fix permissions
chown -R ga:ga "$EML_DIR"
chown ga:ga "$EXPECTED_SUBJECTS_FILE"

# 3. Record initial state of Local Folders
ls -la "${LOCAL_MAIL_DIR}" > /tmp/initial_local_folders_state.txt 2>/dev/null || true

# 4. Start Thunderbird and wait for it to be ready
if ! pgrep -f "thunderbird" > /dev/null; then
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
    sleep 8
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "Mozilla Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Thunderbird" 2>/dev/null || true

# 5. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Prepared 7 .eml files in $EML_DIR"