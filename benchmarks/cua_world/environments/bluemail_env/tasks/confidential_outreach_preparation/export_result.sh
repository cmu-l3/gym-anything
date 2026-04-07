#!/bin/bash
echo "=== Exporting confidential_outreach_preparation results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final visual state
take_screenshot /tmp/task_final.png

# 2. Check if BlueMail is running
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# 3. Check the nominees text file
NOMINEE_FILE="/home/ga/Documents/summit_nominees.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
if [ -f "$NOMINEE_FILE" ]; then
    FILE_EXISTS="true"
    # Read content, stripping whitespace
    FILE_CONTENT=$(cat "$NOMINEE_FILE")
fi

# 4. Parse the most recent Draft email using Python
# We need to extract headers to verify BCC usage
python3 << 'PYEOF'
import os
import email
import json
import glob
import time

drafts_dir = "/home/ga/Maildir/.Drafts"
draft_data = {
    "found": False,
    "to": [],
    "cc": [],
    "bcc": [],
    "subject": "",
    "body_snippet": ""
}

# Find all draft files in cur and new
files = glob.glob(os.path.join(drafts_dir, "cur", "*")) + \
        glob.glob(os.path.join(drafts_dir, "new", "*"))

if files:
    # Get the most recently modified file
    latest_file = max(files, key=os.path.getmtime)
    
    try:
        with open(latest_file, 'rb') as f:
            msg = email.message_from_binary_file(f)
            
            # Helper to extract address list
            def get_addrs(field):
                val = msg.get_all(field, [])
                if not val: return []
                # Simple split by comma if multiple headers not used
                # Ideally use email.utils.getaddresses but keeping it simple for export
                # Combining all headers of type 'field'
                raw = ", ".join(str(v) for v in val)
                return [a.strip() for a in raw.split(',') if a.strip()]

            draft_data["found"] = True
            draft_data["to"] = get_addrs("To")
            draft_data["cc"] = get_addrs("Cc")
            draft_data["bcc"] = get_addrs("Bcc")
            draft_data["subject"] = msg.get("Subject", "")
            
            # Get body snippet
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        draft_data["body_snippet"] = part.get_payload(decode=True).decode('utf-8', errors='ignore')[:200]
                        break
            else:
                draft_data["body_snippet"] = msg.get_payload(decode=True).decode('utf-8', errors='ignore')[:200]
                
    except Exception as e:
        draft_data["error"] = str(e)

# Save draft analysis
with open("/tmp/draft_analysis.json", "w") as f:
    json.dump(draft_data, f)
PYEOF

# 5. Combine everything into result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
DRAFT_JSON=$(cat /tmp/draft_analysis.json 2>/dev/null || echo '{"found": false}')
NOMINEE_CONTENT_ESCAPED=$(echo "$FILE_CONTENT" | python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))")

cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "file_exists": $FILE_EXISTS,
    "file_content": $NOMINEE_CONTENT_ESCAPED,
    "draft": $DRAFT_JSON,
    "task_end_time": $(date +%s)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/draft_analysis.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="