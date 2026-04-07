#!/bin/bash
echo "=== Exporting record_prior_authorization results ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png

PATIENT_ID=$(cat /tmp/target_patient_id 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_auth_count 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_auth_id 2>/dev/null || echo "0")

# 1. Check current authorization count for the patient
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM authorizations WHERE authpatient='$PATIENT_ID'" 2>/dev/null || echo "0")

# 2. Locate the newly created authorization record
# Look for a record created AFTER the task started (id > INITIAL_MAX_ID)
AUTH_RECORD=$(mysql -u freemed -pfreemed freemed -N -B -e "SELECT id, authnum, authpatient, authdtbegin, authdtend FROM authorizations WHERE id > $INITIAL_MAX_ID ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Fallback: search by authorization number in case ID sequences behaved unexpectedly
if [ -z "$AUTH_RECORD" ]; then
    AUTH_RECORD=$(mysql -u freemed -pfreemed freemed -N -B -e "SELECT id, authnum, authpatient, authdtbegin, authdtend FROM authorizations WHERE authnum='AUTH-2025-KMR-90412' ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

AUTH_FOUND="false"
AUTH_ID=""
AUTH_NUM=""
AUTH_PATIENT=""
AUTH_BEGIN=""
AUTH_END=""
FULL_RECORD=""

if [ -n "$AUTH_RECORD" ]; then
    AUTH_FOUND="true"
    AUTH_ID=$(echo "$AUTH_RECORD" | cut -f1)
    AUTH_NUM=$(echo "$AUTH_RECORD" | cut -f2)
    AUTH_PATIENT=$(echo "$AUTH_RECORD" | cut -f3)
    AUTH_BEGIN=$(echo "$AUTH_RECORD" | cut -f4)
    AUTH_END=$(echo "$AUTH_RECORD" | cut -f5)
    
    # 3. Pull the entire row content to verify the comments/description.
    # We aggressively strip quotes, slashes, and non-printable characters to ensure the resulting JSON cannot be corrupted.
    FULL_RECORD=$(mysql -u freemed -pfreemed freemed -e "SELECT * FROM authorizations WHERE id='$AUTH_ID'\G" 2>/dev/null | tr '\n' ' ' | tr -cd '\40-\176' | sed 's/"/ /g' | sed "s/'/ /g" | sed 's/\\/ /g')
fi

# 4. Generate JSON results structure safely via a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": "$PATIENT_ID",
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "initial_max_id": $INITIAL_MAX_ID,
    "auth_found": $AUTH_FOUND,
    "auth_record": {
        "id": "$AUTH_ID",
        "authnum": "$AUTH_NUM",
        "authpatient": "$AUTH_PATIENT",
        "authdtbegin": "$AUTH_BEGIN",
        "authdtend": "$AUTH_END",
        "full_text": "$FULL_RECORD"
    }
}
EOF

# Move payload to standardized location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON Payload Exported:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="