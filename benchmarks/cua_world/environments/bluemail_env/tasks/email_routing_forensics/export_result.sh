#!/bin/bash
echo "=== Exporting email_routing_forensics result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Report File Check
REPORT_PATH="/home/ga/Documents/forensic_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE="0"
REPORT_MODIFIED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    # Read content (escape for JSON)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED_DURING_TASK="true"
    fi
else
    REPORT_CONTENT='""' # Empty JSON string
fi

# 2. Evidence Folder Check
MAILDIR="/home/ga/Maildir"
EVIDENCE_FOLDER_NAME="Forensic-Evidence"
EVIDENCE_FOLDER_PATH=""
EVIDENCE_EXISTS="false"
EVIDENCE_COUNT=0

# Find folder case-insensitively
for d in "$MAILDIR"/.*; do
    if [ -d "$d" ]; then
        dirname=$(basename "$d" | sed 's/^\.//')
        if echo "$dirname" | grep -qi "^${EVIDENCE_FOLDER_NAME}$"; then
            EVIDENCE_EXISTS="true"
            EVIDENCE_FOLDER_PATH="$d"
            # Count emails in cur and new
            count_cur=$(ls -1 "$d/cur" 2>/dev/null | wc -l)
            count_new=$(ls -1 "$d/new" 2>/dev/null | wc -l)
            EVIDENCE_COUNT=$((count_cur + count_new))
            break
        fi
    fi
done

# 3. Extract Ground Truth Headers from Evidence Folder (for verification)
# We want to know if the user actually put spam emails there, and what their headers are.
PYTHON_HEADER_EXTRACTOR=$(cat <<END
import os
import json
import re
import email
from email import policy

evidence_path = "$EVIDENCE_FOLDER_PATH"
data = []

if evidence_path and os.path.exists(evidence_path):
    for subdir in ["cur", "new"]:
        p = os.path.join(evidence_path, subdir)
        if os.path.exists(p):
            for f in os.listdir(p):
                fpath = os.path.join(p, f)
                if os.path.isfile(fpath):
                    try:
                        with open(fpath, 'rb') as ef:
                            msg = email.message_from_binary_file(ef, policy=policy.default)
                            
                            # Extract key headers
                            headers = {
                                "subject": msg.get("Subject", ""),
                                "from": msg.get("From", ""),
                                "return_path": msg.get("Return-Path", ""),
                                "received": str(msg.get_all("Received", [])),
                                "x_mailer": msg.get("X-Mailer", "")
                            }
                            
                            # Extract IPs from headers
                            ip_pattern = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b')
                            all_headers = str(msg.values())
                            ips = list(set(ip_pattern.findall(all_headers)))
                            headers["extracted_ips"] = ips
                            
                            data.append(headers)
                    except Exception as e:
                        continue

print(json.dumps(data))
END
)

if [ "$EVIDENCE_EXISTS" = "true" ]; then
    EVIDENCE_HEADERS=$(python3 -c "$PYTHON_HEADER_EXTRACTOR")
else
    EVIDENCE_HEADERS="[]"
fi

# 4. Check for Draft/Sent Email to Abuse Team
DRAFT_CHECK=$(python3 <<END
import os, json, email, re
from email import policy

maildir = "$MAILDIR"
abuse_email = "abuse-reports@company.com"
found = False
details = {}

for folder in [".Drafts", ".Sent"]:
    for subdir in ["cur", "new"]:
        path = os.path.join(maildir, folder, subdir)
        if not os.path.exists(path): continue
        
        for f in os.listdir(path):
            try:
                with open(os.path.join(path, f), 'rb') as fp:
                    msg = email.message_from_binary_file(fp, policy=policy.default)
                    
                    # Check To/Cc/Bcc
                    recipients = str(msg.get("To", "")) + str(msg.get("Cc", "")) + str(msg.get("Bcc", ""))
                    
                    if abuse_email in recipients:
                        found = True
                        details = {
                            "subject": msg.get("Subject", ""),
                            "body_snippet": str(msg.get_body(preferencelist=('plain')).get_content())[:200] if msg.get_body() else ""
                        }
                        break
            except: continue
    if found: break

print(json.dumps({"found": found, "details": details}))
END
)

# 5. Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Construct Result JSON
cat > /tmp/task_result.json <<EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_modified_during_task": $REPORT_MODIFIED_DURING_TASK,
    "report_content": $REPORT_CONTENT,
    "evidence_folder_exists": $EVIDENCE_EXISTS,
    "evidence_email_count": $EVIDENCE_COUNT,
    "evidence_headers": $EVIDENCE_HEADERS,
    "abuse_email_check": $DRAFT_CHECK
}
EOF

chmod 666 /tmp/task_result.json
echo "Export complete."