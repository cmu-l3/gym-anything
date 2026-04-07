#!/bin/bash
echo "=== Exporting sender_contact_harvest results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Contact List File
OUTPUT_PATH="/home/ga/Documents/contact_list.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
LINE_COUNT=0
UNIQUE_COUNT=0
VALID_MATCH_COUNT=0
VALID_MATCH_PCT=0.0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Parse Agent Output
    # Extract valid email patterns, normalize to lowercase, sort unique
    grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$OUTPUT_PATH" | \
        tr '[:upper:]' '[:lower:]' | \
        sort -u > /tmp/agent_extracted.txt
    
    UNIQUE_COUNT=$(wc -l < /tmp/agent_extracted.txt)
    LINE_COUNT=$(wc -l < "$OUTPUT_PATH")

    # Compare with Ground Truth (generated in setup)
    if [ -f /tmp/ground_truth_senders.txt ]; then
        # Count lines that appear in both files
        VALID_MATCH_COUNT=$(comm -12 /tmp/ground_truth_senders.txt /tmp/agent_extracted.txt | wc -l)
        
        # Calculate percentage accuracy (precision)
        if [ "$UNIQUE_COUNT" -gt 0 ]; then
            VALID_MATCH_PCT=$(echo "scale=2; ($VALID_MATCH_COUNT / $UNIQUE_COUNT) * 100" | bc)
        fi
    fi
fi

# 2. Check Drafts
DRAFT_FOUND="false"
DRAFT_RECIPIENT_MATCH="false"
DRAFT_SUBJECT_MATCH="false"
DRAFT_CONTENT_KEYWORDS_MATCH="false"
DRAFT_DETAILS=""

# Python script to parse drafts robustly
python3 << 'PYEOF'
import os
import email
import json
import re

maildir = "/home/ga/Maildir"
draft_dirs = [os.path.join(maildir, ".Drafts", "cur"), os.path.join(maildir, ".Drafts", "new")]
sent_dirs = [os.path.join(maildir, ".Sent", "cur"), os.path.join(maildir, ".Sent", "new")]
all_dirs = draft_dirs + sent_dirs

target_email = "meetup-announce@techgroup.org"
keywords = ["meetup", "event", "contact", "list", "compiled"]
found_draft = {}

for d in all_dirs:
    if not os.path.exists(d): continue
    for filename in os.listdir(d):
        filepath = os.path.join(d, filename)
        if not os.path.isfile(filepath): continue
        
        try:
            with open(filepath, 'rb') as f:
                msg = email.message_from_binary_file(f)
            
            to_addr = msg.get("To", "").lower()
            subject = msg.get("Subject", "").lower()
            
            # Simple body extraction
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain":
                        body += part.get_payload(decode=True).decode(errors='ignore')
            else:
                body = msg.get_payload(decode=True).decode(errors='ignore')
            body = body.lower()

            # Check logic
            if target_email in to_addr:
                found_draft = {
                    "found": True,
                    "recipient_correct": True,
                    "subject_match": "announcement" in subject or "meetup" in subject,
                    "keyword_match": sum(1 for k in keywords if k in body or k in subject) >= 2,
                    "path": filepath
                }
                break # Stop if we find the target draft
        except Exception as e:
            continue
    if found_draft: break

with open("/tmp/draft_analysis.json", "w") as f:
    json.dump(found_draft if found_draft else {"found": False}, f)
PYEOF

if [ -f "/tmp/draft_analysis.json" ]; then
    DRAFT_DETAILS=$(cat /tmp/draft_analysis.json)
fi

# 3. Check Inbox Integrity
INITIAL_INBOX=$(cat /tmp/initial_inbox_count.txt 2>/dev/null || echo "50")
CURRENT_INBOX=$(ls -1 /home/ga/Maildir/cur/ /home/ga/Maildir/new/ 2>/dev/null | grep -v '^\.' | wc -l)
INBOX_PRESERVED="false"
# Allow small fluctuation but main corpus should remain
if [ "$CURRENT_INBOX" -ge $((INITIAL_INBOX - 2)) ]; then
    INBOX_PRESERVED="true"
fi

# 4. Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "extracted_unique_count": $UNIQUE_COUNT,
    "valid_match_count": $VALID_MATCH_COUNT,
    "valid_match_pct": $VALID_MATCH_PCT,
    "inbox_preserved": $INBOX_PRESERVED,
    "inbox_count_initial": $INITIAL_INBOX,
    "inbox_count_final": $CURRENT_INBOX,
    "draft_analysis": $DRAFT_DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="