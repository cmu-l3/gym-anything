#!/bin/bash
echo "=== Exporting GDPR Erasure Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

TARGET_EMAIL="john.smith@example.com"
NEW_EMAIL="erased_john_smith@agency.local"
AUDIT_FILE="/home/ga/gdpr_audit.txt"
INITIAL_STAYS=$(cat /tmp/initial_stays_count.txt 2>/dev/null || echo "0")
ORIGINAL_RID=$(cat /tmp/target_rid.txt 2>/dev/null || echo "")

# --- Database Queries ---

# 1. Check if old email still exists
OLD_EMAIL_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Profiles WHERE Email='$TARGET_EMAIL'" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "-1")

# 2. Check new profile data
NEW_PROFILE_JSON=$(orientdb_sql "demodb" "SELECT Name, Surname, Gender, Birthday, Nationality, out('HasStayed').size() as stays, both('HasFriend').size() as friends, @rid as rid FROM Profiles WHERE Email='$NEW_EMAIL'")

# Parse JSON with python for robustness
PARSED_RESULT=$(echo "$NEW_PROFILE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    res = data.get('result', [])
    if not res:
        print(json.dumps({'found': False}))
    else:
        rec = res[0]
        print(json.dumps({
            'found': True,
            'name': rec.get('Name'),
            'surname': rec.get('Surname'),
            'gender': rec.get('Gender'),
            'birthday': rec.get('Birthday'),
            'nationality': rec.get('Nationality'),
            'stay_count': rec.get('stays', 0),
            'friend_count': rec.get('friends', 0),
            'rid': rec.get('rid')
        }))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")

# 3. Check Audit File
AUDIT_FILE_EXISTS="false"
AUDIT_CONTENT=""
AUDIT_RID_MATCH="false"

if [ -f "$AUDIT_FILE" ]; then
    AUDIT_FILE_EXISTS="true"
    AUDIT_CONTENT=$(cat "$AUDIT_FILE")
    # Check if the file contains the correct RID
    if [[ "$AUDIT_CONTENT" == *"$ORIGINAL_RID"* ]]; then
        AUDIT_RID_MATCH="true"
    fi
fi

# Construct Result JSON
TERM_JSON=$(mktemp /tmp/gdpr_result.XXXXXX.json)
cat > "$TERM_JSON" << EOF
{
    "old_email_count": $OLD_EMAIL_COUNT,
    "initial_stay_count": $INITIAL_STAYS,
    "original_rid": "$ORIGINAL_RID",
    "new_profile": $PARSED_RESULT,
    "audit_file": {
        "exists": $AUDIT_FILE_EXISTS,
        "content_preview": "$(echo $AUDIT_CONTENT | head -c 100)",
        "rid_match": $AUDIT_RID_MATCH
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TERM_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json