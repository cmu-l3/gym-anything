#!/bin/bash
echo "=== Exporting remove_large_attachments result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Thunderbird is running
APP_RUNNING=$(is_thunderbird_running && echo "true" || echo "false")

echo "Parsing Inbox for verification..."
python3 -c "
import mailbox, json, os

inbox_path = '/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox'
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': str('$APP_RUNNING').lower() == 'true',
    'total_emails': 0,
    'target_emails': {},
    'inbox_mtime': 0
}

if os.path.exists(inbox_path):
    result['inbox_mtime'] = int(os.path.getmtime(inbox_path))
    try:
        mbox = mailbox.mbox(inbox_path)
        result['total_emails'] = len(mbox)
        
        for msg in mbox:
            subj = msg.get('Subject', '')
            if subj and subj.startswith('Case Evidence:'):
                result['target_emails'][subj] = {'size': len(msg.as_bytes())}
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="