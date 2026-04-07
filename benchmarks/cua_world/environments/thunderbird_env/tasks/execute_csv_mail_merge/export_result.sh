#!/bin/bash
set -euo pipefail

echo "=== Exporting Mail Merge result ==="

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Parse Outbox with Python to output clean JSON structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

export TASK_START
export TASK_END

python3 << 'EOF' > "$TEMP_JSON"
import mailbox
import json
import os

outbox_path = "/home/ga/.thunderbird/default-release/Mail/Local Folders/Unsent Messages"
result = {
    "task_start": int(os.environ.get("TASK_START", "0")),
    "task_end": int(os.environ.get("TASK_END", "0")),
    "file_exists": False,
    "file_size": 0,
    "file_mtime": 0,
    "emails": [],
    "screenshot_path": "/tmp/task_final.png"
}

if os.path.exists(outbox_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(outbox_path)
    result["file_mtime"] = os.path.getmtime(outbox_path)
    
    try:
        mbox = mailbox.mbox(outbox_path)
        for msg in mbox:
            subject = str(msg.get('Subject', ''))
            to = str(msg.get('To', ''))
            
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        payload = part.get_payload(decode=True)
                        if payload:
                            body = payload.decode('utf-8', errors='ignore')
                        break
            else:
                payload = msg.get_payload(decode=True)
                if payload:
                    body = payload.decode('utf-8', errors='ignore')
            
            result["emails"].append({
                "to": to,
                "subject": subject,
                "body": body
            })
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result, indent=2))
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="