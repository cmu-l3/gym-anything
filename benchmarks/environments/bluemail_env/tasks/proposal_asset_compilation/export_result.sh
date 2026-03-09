#!/bin/bash
echo "=== Exporting proposal_asset_compilation result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# Verify File System Artifacts (The Downloads)
# ------------------------------------------------------------------
TARGET_DIR="/home/ga/Documents/Falcon_Assets"
FOLDER_EXISTS="false"
FILES_FOUND=()
FILES_HASHES="{}"

if [ -d "$TARGET_DIR" ]; then
    FOLDER_EXISTS="true"
    
    # Check for expected files and calculate their hashes
    FILES_HASHES=$(python3 << 'PYEOF'
import os
import hashlib
import json

target_dir = "/home/ga/Documents/Falcon_Assets"
files_data = {}

if os.path.exists(target_dir):
    for f in os.listdir(target_dir):
        full_path = os.path.join(target_dir, f)
        if os.path.isfile(full_path):
            try:
                with open(full_path, 'rb') as file:
                    content = file.read()
                    md5 = hashlib.md5(content).hexdigest()
                    mtime = os.path.getmtime(full_path)
                    files_data[f] = {
                        "md5": md5, 
                        "mtime": mtime,
                        "size": len(content)
                    }
            except:
                pass

print(json.dumps(files_data))
PYEOF
)
fi

# ------------------------------------------------------------------
# Verify Sent Email
# ------------------------------------------------------------------
SENT_EMAIL_INFO=$(python3 << 'PYEOF'
import os
import email
import json
import email.policy

maildir_sent = "/home/ga/Maildir/.Sent"
task_start = float(open('/tmp/task_start_time.txt').read().strip())
sent_emails = []

# Check new and cur in .Sent
for subdir in ["new", "cur"]:
    path = os.path.join(maildir_sent, subdir)
    if os.path.exists(path):
        for f in os.listdir(path):
            full_path = os.path.join(path, f)
            # Check if file was modified after task start
            if os.path.getmtime(full_path) > task_start:
                try:
                    with open(full_path, 'rb') as fp:
                        msg = email.message_from_binary_file(fp, policy=email.policy.default)
                        sent_emails.append({
                            "to": msg['to'],
                            "subject": msg['subject'],
                            "date": msg['date']
                        })
                except Exception as e:
                    pass

print(json.dumps(sent_emails))
PYEOF
)

# ------------------------------------------------------------------
# Load Expected Hashes (generated in setup)
# ------------------------------------------------------------------
EXPECTED_HASHES=$(cat /tmp/expected_asset_hashes.json 2>/dev/null || echo "{}")

# ------------------------------------------------------------------
# Construct Result JSON
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "folder_exists": $FOLDER_EXISTS,
    "found_files": $FILES_HASHES,
    "expected_hashes": $EXPECTED_HASHES,
    "sent_emails": $SENT_EMAIL_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="