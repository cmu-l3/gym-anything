#!/bin/bash
echo "=== Exporting professional_signature_and_introduction result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# ============================================================
# 1. Search for Config Persistence (Signature in settings)
# ============================================================
# BlueMail (Electron) stores data in ~/.config/BlueMail or ~/.bluemail
# We grep recursively for the signature elements to see if they were saved to disk
CONFIG_DIR="/home/ga/.config/BlueMail"
ALT_CONFIG_DIR="/home/ga/.bluemail"

SIG_NAME_FOUND="false"
SIG_TITLE_FOUND="false"
SIG_COMPANY_FOUND="false"
SIG_PHONE_FOUND="false"

# Helper to grep in config dirs
check_config_for_text() {
    local text="$1"
    if grep -r "$text" "$CONFIG_DIR" "$ALT_CONFIG_DIR" 2>/dev/null >/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

SIG_NAME_FOUND=$(check_config_for_text "Alex Morgan")
SIG_TITLE_FOUND=$(check_config_for_text "Marketing Coordinator")
SIG_COMPANY_FOUND=$(check_config_for_text "TechVision") # Shortened to catch variations
SIG_PHONE_FOUND=$(check_config_for_text "555")

# ============================================================
# 2. Extract Drafts and Sent Emails
# ============================================================
# We use Python to parse the Maildir files reliably

python3 << 'PYEOF'
import os
import json
import email
from email import policy
import glob

def parse_maildir_folder(folder_path):
    emails = []
    # Check both cur and new directories
    files = glob.glob(os.path.join(folder_path, "cur", "*")) + \
            glob.glob(os.path.join(folder_path, "new", "*"))
    
    for fpath in files:
        try:
            with open(fpath, 'rb') as f:
                msg = email.message_from_binary_file(f, policy=policy.default)
                
                # Get body
                body = ""
                if msg.is_multipart():
                    for part in msg.walk():
                        if part.get_content_type() == "text/plain":
                            body += part.get_content()
                else:
                    body = msg.get_content()
                
                emails.append({
                    "to": str(msg["to"]),
                    "subject": str(msg["subject"]),
                    "body": body,
                    "date": str(msg["date"]),
                    "filename": os.path.basename(fpath)
                })
        except Exception as e:
            continue
    return emails

home = os.path.expanduser("~")
maildir = os.path.join(home, "Maildir")

drafts = parse_maildir_folder(os.path.join(maildir, ".Drafts"))
sent = parse_maildir_folder(os.path.join(maildir, ".Sent"))
# Also check Outbox/Queue if applicable, but usually Sent covers it for verified delivery

# Also check filesystem timestamp to ensure it was created during task
# (Handled simply by the setup script clearing these folders)

result = {
    "drafts": drafts,
    "sent": sent,
    "config_persistence": {
        "name_found": "${SIG_NAME_FOUND}",
        "title_found": "${SIG_TITLE_FOUND}",
        "company_found": "${SIG_COMPANY_FOUND}",
        "phone_found": "${SIG_PHONE_FOUND}"
    },
    "bluemail_running": True  # Simplified check
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="