#!/bin/bash
echo "=== Exporting recover_deleted_folder result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot before any manipulation
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Thunderbird if it's still running to ensure mbox files are flushed to disk
if pgrep -f "thunderbird" > /dev/null; then
    echo "Thunderbird is still running. Attempting graceful shutdown to flush MSF indexes..."
    su - ga -c "DISPLAY=:1 wmctrl -c 'Mozilla Thunderbird'" 2>/dev/null || true
    sleep 4
fi

# Run python script to parse the mbox files directly and export clean JSON
python3 << 'EOF'
import os
import json
import re

PROFILE_DIR = "/home/ga/.thunderbird/default-release"
ROOT_MBOX = f"{PROFILE_DIR}/Mail/Local Folders/Q4_Audit"
TRASH_MBOX = f"{PROFILE_DIR}/Mail/Local Folders/Trash.sbd/Q4_Audit"

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    start_time = 0

result = {
    "root_exists": os.path.exists(ROOT_MBOX),
    "trash_exists": os.path.exists(TRASH_MBOX),
    "root_mtime": int(os.path.getmtime(ROOT_MBOX)) if os.path.exists(ROOT_MBOX) else 0,
    "urgent_starred": False,
    "urgent_unread": False,
    "all_unread": True,
    "total_emails": 0,
    "task_start_time": start_time
}

if result["root_exists"]:
    try:
        with open(ROOT_MBOX, 'r', errors='replace') as f:
            content = f.read()

        # Split mbox by "From " boundary
        messages = content.split('\nFrom - ')
        
        # In case the first message doesn't start with a newline
        if messages and not messages[0].startswith('From - ') and 'From - ' in content[:20]:
            messages[0] = content[content.find('From - ') + 7:]

        for msg in messages:
            if not msg.strip(): 
                continue
                
            result["total_emails"] += 1
            
            # X-Mozilla-Status contains the bit flags for read/unread/starred
            status_match = re.search(r'X-Mozilla-Status: ([0-9a-fA-F]+)', msg)
            subject_match = re.search(r'Subject: (.*?)\n', msg)
            
            status = int(status_match.group(1), 16) if status_match else 0
            subject = subject_match.group(1).strip() if subject_match else ""
            
            # Read bit is 1 (0x0001)
            is_read = (status & 1) != 0
            # Starred/Flagged bit is 4 (0x0004)
            is_starred = (status & 4) != 0
            
            if is_read:
                result["all_unread"] = False
                
            if "URGENT: Missing Signatures" in subject:
                result["urgent_starred"] = is_starred
                result["urgent_unread"] = not is_read

    except Exception as e:
        result["error"] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="