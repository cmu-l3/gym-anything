#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png ga

# Task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if BlueMail is running
BM_RUNNING=$(is_bluemail_running && echo "true" || echo "false")

# ============================================================
# Python script to analyze Maildir content
# ============================================================
cat > /tmp/analyze_maildir.py << 'PYEOF'
import os
import json
import re
import glob

MAILDIR = "/home/ga/Maildir"
TASK_START = int(os.environ.get('TASK_START', 0))

def parse_email_content(filepath):
    """Extract subject and body for keyword analysis."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        # Simple heuristic parsing
        headers = {}
        body = ""
        
        parts = content.split('\n\n', 1)
        header_block = parts[0]
        if len(parts) > 1:
            body = parts[1]
            
        for line in header_block.split('\n'):
            if ':' in line:
                key, val = line.split(':', 1)
                headers[key.lower().strip()] = val.strip()
                
        return {
            'subject': headers.get('subject', ''),
            'to': headers.get('to', ''),
            'body': body[:5000].lower(), # Lowercase for keyword matching
            'full_text': (headers.get('subject', '') + " " + body[:5000]).lower()
        }
    except Exception as e:
        return {'subject': 'Error', 'body': '', 'full_text': '', 'error': str(e)}

def scan_folders():
    structure = {
        'projects_root': False,
        'subfolders': {},
        'drafts': [],
        'sent': []
    }
    
    # Check for Projects root (Dovecot format: .Projects)
    if os.path.exists(os.path.join(MAILDIR, '.Projects')):
        structure['projects_root'] = True
        
    # Check for subfolders (Dovecot format: .Projects.Project-Shield)
    # We allow some flexibility in case/naming, but map to canonical IDs
    
    # Map of canonical keys to regex patterns for folder detection
    targets = {
        'shield': r'\.Projects\.Project[-_]?Shield',
        'mind': r'\.Projects\.Project[-_]?Mind',
        'grid': r'\.Projects\.Project[-_]?Grid'
    }
    
    # Scan all directories in Maildir
    all_dirs = [d for d in os.listdir(MAILDIR) if os.path.isdir(os.path.join(MAILDIR, d))]
    
    for d in all_dirs:
        # Check against targets
        for key, pattern in targets.items():
            if re.match(pattern, d, re.IGNORECASE):
                # Found a target folder
                emails = []
                # Read cur and new
                for subdir in ['cur', 'new']:
                    path = os.path.join(MAILDIR, d, subdir)
                    if os.path.exists(path):
                        for f in os.listdir(path):
                            fpath = os.path.join(path, f)
                            if os.path.isfile(fpath):
                                email_data = parse_email_content(fpath)
                                emails.append(email_data)
                
                structure['subfolders'][key] = {
                    'folder_name': d,
                    'emails': emails,
                    'count': len(emails)
                }

    # Scan Drafts
    drafts_dir = os.path.join(MAILDIR, '.Drafts')
    for subdir in ['cur', 'new']:
        path = os.path.join(drafts_dir, subdir)
        if os.path.exists(path):
            for f in os.listdir(path):
                fpath = os.path.join(path, f)
                if os.path.isfile(fpath):
                    # Check timestamp to ensure it was created during task
                    mtime = os.path.getmtime(fpath)
                    if mtime > TASK_START:
                        structure['drafts'].append(parse_email_content(fpath))

    # Scan Sent
    sent_dir = os.path.join(MAILDIR, '.Sent')
    for subdir in ['cur', 'new']:
        path = os.path.join(sent_dir, subdir)
        if os.path.exists(path):
            for f in os.listdir(path):
                fpath = os.path.join(path, f)
                if os.path.isfile(fpath):
                    mtime = os.path.getmtime(fpath)
                    if mtime > TASK_START:
                        structure['sent'].append(parse_email_content(fpath))
                        
    return structure

result = scan_folders()
print(json.dumps(result))
PYEOF

# Run python script and capture output
export TASK_START
ANALYSIS_JSON=$(python3 /tmp/analyze_maildir.py)

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bluemail_running": $BM_RUNNING,
    "maildir_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="