#!/bin/bash
echo "=== Exporting Offline Reference Archive Creation results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic State Checks
BM_RUNNING="false"
if is_bluemail_running; then
    BM_RUNNING="true"
fi

# 3. Analyze Target Directory
TARGET_DIR="/home/ga/Documents/OfflineDocs"
DIR_EXISTS="false"
FILE_COUNT=0
RELEVANT_CONTENT_FOUND="false"
FILES_METADATA="[]"

if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
    # Count non-hidden files
    FILE_COUNT=$(find "$TARGET_DIR" -maxdepth 1 -type f -not -name '.*' | wc -l)
    
    # Check content relevance (grep for keywords in the saved files)
    # We use grep -a to handle PDF binaries as text best-effort
    if grep -raiE "RAID|Kernel|scsi|panic" "$TARGET_DIR" > /dev/null 2>&1; then
        RELEVANT_CONTENT_FOUND="true"
    fi

    # Get file list with sizes
    FILES_METADATA=$(python3 << PYEOF
import os, json
files = []
try:
    target = "$TARGET_DIR"
    for f in os.listdir(target):
        path = os.path.join(target, f)
        if os.path.isfile(path) and not f.startswith('.'):
            files.append({
                "name": f,
                "size": os.path.getsize(path),
                "extension": os.path.splitext(f)[1].lower()
            })
except:
    pass
print(json.dumps(files))
PYEOF
)
fi

# 4. Analyze Drafts for Confirmation Email
DRAFT_FOUND="false"
DRAFT_SUBJECT=""
DRAFTS_DIR="/home/ga/Maildir/.Drafts"
TARGET_RECIPIENT="dispatch@company.com"

# Parse draft files in Maildir
if [ -d "$DRAFTS_DIR/cur" ] || [ -d "$DRAFTS_DIR/new" ]; then
    # Simple python script to parse headers
    DRAFT_INFO=$(python3 << PYEOF
import os, email, json

draft_dirs = ["$DRAFTS_DIR/cur", "$DRAFTS_DIR/new"]
found = False
subject_found = ""

for d in draft_dirs:
    if not os.path.isdir(d): continue
    for fname in os.listdir(d):
        path = os.path.join(d, fname)
        try:
            with open(path, 'rb') as f:
                msg = email.message_from_binary_file(f)
                to_addr = msg.get('To', '').lower()
                if "$TARGET_RECIPIENT" in to_addr:
                    found = True
                    subject_found = msg.get('Subject', '')
                    break
        except:
            continue
    if found: break

print(json.dumps({"found": found, "subject": subject_found}))
PYEOF
)
    DRAFT_FOUND=$(echo "$DRAFT_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['found'])")
    DRAFT_SUBJECT=$(echo "$DRAFT_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['subject'])")
fi

# 5. Compile Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bluemail_running": $BM_RUNNING,
    "dir_exists": $DIR_EXISTS,
    "file_count": $FILE_COUNT,
    "files_metadata": $FILES_METADATA,
    "relevant_content_found": $RELEVANT_CONTENT_FOUND,
    "draft_found": $DRAFT_FOUND,
    "draft_subject": "$DRAFT_SUBJECT",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="