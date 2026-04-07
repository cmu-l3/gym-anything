#!/bin/bash
echo "=== Exporting Vendor Communication Audit Results ==="

source /workspace/scripts/task_utils.sh

MAILDIR="/home/ga/Maildir"
AUDIT_FOLDER_NAME="Audit-SourceForge"
AUDIT_DIR="${MAILDIR}/.${AUDIT_FOLDER_NAME}"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png ga

# 2. Check BlueMail Status
APP_RUNNING="false"
if is_bluemail_running; then
    APP_RUNNING="true"
fi

# 3. Analyze File System State

# Initialize counters
AUDIT_FOLDER_EXISTS="false"
TOTAL_MOVED_COUNT=0
SF_MATCH_COUNT=0
FLAGGED_COUNT=0
DRAFT_EXISTS="false"
DRAFT_RECIPIENT_MATCH="false"
REPORTED_COUNT_IN_DRAFT=0

# Check if Audit folder exists
if [ -d "$AUDIT_DIR" ]; then
    AUDIT_FOLDER_EXISTS="true"
    
    # Count emails in cur and new
    # Note: Use nullglob logic or find to handle empty dirs safely
    MOVED_FILES=$(find "${AUDIT_DIR}/cur" "${AUDIT_DIR}/new" -type f 2>/dev/null)
    TOTAL_MOVED_COUNT=$(echo "$MOVED_FILES" | grep -v "^$" | wc -l)
    
    if [ "$TOTAL_MOVED_COUNT" -gt 0 ]; then
        # Check relevance: How many contain "sourceforge.net"?
        # We use xargs grep -l to list matching files, then count lines
        SF_MATCH_COUNT=$(echo "$MOVED_FILES" | xargs grep -li "sourceforge.net" 2>/dev/null | wc -l)
        
        # Check flags: Filenames ending in "F" (e.g., :2,SF or :2,F) indicate flagged/starred
        # Standard Maildir flag 'F' = Flagged
        FLAGGED_COUNT=$(echo "$MOVED_FILES" | grep "F$" 2>/dev/null | wc -l)
        
        # Also check for 'F' in the flags section generally (e.g. :2,FRS)
        # Grep regex: :2,.*F
        FLAGGED_COUNT_ROBUST=$(echo "$MOVED_FILES" | grep ":2,.*F" 2>/dev/null | wc -l)
        # Use the robust count
        FLAGGED_COUNT=$FLAGGED_COUNT_ROBUST
    fi
fi

# Check Drafts
DRAFTS_DIR="${MAILDIR}/.Drafts"
DRAFT_INFO=""

# We need to find a draft to legal@company.com
# We will use a python snippet to parse the drafts because bash parsing of emails is fragile
python3 << PYEOF > /tmp/draft_analysis.json
import os
import email
import json
import re

drafts_dir = "${DRAFTS_DIR}"
result = {
    "found": False,
    "recipient_correct": False,
    "reported_count": 0,
    "subject": ""
}

target_recipient = "legal@company.com"
number_pattern = re.compile(r'\b(\d+)\b')

if os.path.exists(drafts_dir):
    for subdir in ["cur", "new"]:
        path = os.path.join(drafts_dir, subdir)
        if not os.path.exists(path):
            continue
            
        for filename in os.listdir(path):
            filepath = os.path.join(path, filename)
            if not os.path.isfile(filepath):
                continue
                
            try:
                with open(filepath, 'rb') as f:
                    msg = email.message_from_binary_file(f)
                
                # Check recipient
                to_addr = msg.get("To", "")
                if target_recipient.lower() in to_addr.lower():
                    result["found"] = True
                    result["recipient_correct"] = True
                    result["subject"] = msg.get("Subject", "")
                    
                    # Extract body to find the reported number
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body += part.get_payload(decode=True).decode('utf-8', errors='ignore')
                    else:
                        body = msg.get_payload(decode=True).decode('utf-8', errors='ignore')
                    
                    # Find numbers in body
                    numbers = number_pattern.findall(body)
                    # We assume the last number mentioned or the one closest to the moved count might be it
                    # But typically agents write "I moved 23 emails".
                    if numbers:
                        # Simply take the first number found for now, or list all
                        result["reported_count"] = int(numbers[0])
                    
                    break # Stop after finding the first matching draft
            except Exception as e:
                continue

print(json.dumps(result))
PYEOF

# Read python output
if [ -f /tmp/draft_analysis.json ]; then
    DRAFT_EXISTS=$(jq -r .found /tmp/draft_analysis.json)
    DRAFT_RECIPIENT_MATCH=$(jq -r .recipient_correct /tmp/draft_analysis.json)
    REPORTED_COUNT_IN_DRAFT=$(jq -r .reported_count /tmp/draft_analysis.json)
fi

# 4. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "app_running": $APP_RUNNING,
    "audit_folder_exists": $AUDIT_FOLDER_EXISTS,
    "total_moved_count": $TOTAL_MOVED_COUNT,
    "sf_match_count": $SF_MATCH_COUNT,
    "flagged_count": $FLAGGED_COUNT,
    "draft_exists": $DRAFT_EXISTS,
    "draft_recipient_correct": $DRAFT_RECIPIENT_MATCH,
    "reported_count_in_draft": $REPORTED_COUNT_IN_DRAFT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="