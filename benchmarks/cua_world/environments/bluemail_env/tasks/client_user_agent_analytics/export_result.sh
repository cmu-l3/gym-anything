#!/bin/bash
echo "=== Exporting client_user_agent_analytics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Python Analysis Script
# ============================================================
# We use Python to parse the Maildir recursively.
# We need to extract headers from emails in UA-* folders to verify sorting accuracy.

python3 << 'PYEOF'
import os
import json
import re
import email
from email.parser import BytesParser
from email import policy

MAILDIR = "/home/ga/Maildir"
PREFIX = "UA-"

def get_headers(fpath):
    """Extract relevant UA headers from an email file."""
    try:
        with open(fpath, 'rb') as f:
            msg = BytesParser(policy=policy.default).parse(f)
        
        ua = msg.get('User-Agent', '')
        x_mailer = msg.get('X-Mailer', '')
        subject = msg.get('Subject', '')
        
        # Combined string for searching
        raw_headers = f"User-Agent: {ua}\nX-Mailer: {x_mailer}"
        
        return {
            'subject': subject,
            'user_agent': ua,
            'x_mailer': x_mailer,
            'raw': raw_headers
        }
    except Exception as e:
        return {'error': str(e)}

def parse_drafts():
    """Parse drafts to find the report."""
    drafts = []
    draft_dir = os.path.join(MAILDIR, '.Drafts', 'cur')
    if os.path.exists(draft_dir):
        for fname in os.listdir(draft_dir):
            fpath = os.path.join(draft_dir, fname)
            if os.path.isfile(fpath):
                with open(fpath, 'rb') as f:
                    msg = BytesParser(policy=policy.default).parse(f)
                drafts.append({
                    'to': msg.get('To', ''),
                    'subject': msg.get('Subject', ''),
                    'body': msg.get_body(preferencelist=('plain')).get_content() if msg.get_body() else ""
                })
    return drafts

def analyze_folders():
    """Find UA-* folders and analyze their contents."""
    results = {
        'ua_folders': {},
        'drafts': parse_drafts(),
        'bluemail_running': False
    }

    # Check for folders starting with .UA- (Maildir hidden folders)
    for entry in os.listdir(MAILDIR):
        if entry.startswith(f".{PREFIX}"):
            folder_name = entry[1:] # Remove leading dot
            folder_path = os.path.join(MAILDIR, entry)
            
            emails = []
            # Check cur and new
            for subdir in ['cur', 'new']:
                spath = os.path.join(folder_path, subdir)
                if os.path.isdir(spath):
                    for fname in os.listdir(spath):
                        fpath = os.path.join(spath, fname)
                        if os.path.isfile(fpath):
                            emails.append(get_headers(fpath))
            
            results['ua_folders'][folder_name] = emails
            
    return results

# Generate result
data = analyze_folders()

# Check if app is running (using pgrep passed from shell would be easier, but we do it here)
# We'll handle app running check in bash and merge
with open('/tmp/py_analysis.json', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

# Merge with shell-based checks
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# Create final JSON
jq -n --argfile analysis /tmp/py_analysis.json \
      --arg bm_running "$BM_RUNNING" \
      --arg timestamp "$(date -Iseconds)" \
      '{
         analysis: $analysis,
         bluemail_running: ($bm_running == "true"),
         timestamp: $timestamp
       }' > /tmp/task_result.json

# Cleanup
rm -f /tmp/py_analysis.json

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="