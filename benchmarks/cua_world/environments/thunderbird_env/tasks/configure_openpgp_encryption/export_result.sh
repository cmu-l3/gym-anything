#!/bin/bash
set -euo pipefail

echo "=== Exporting OpenPGP task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PUBKEY_PATH="/home/ga/Documents/testuser_pubkey.asc"
PREFS_FILE="/home/ga/.thunderbird/default-release/prefs.js"

# 1. Check if public key file exists and grab its properties
PUBKEY_EXISTS="false"
PUBKEY_CREATED_DURING_TASK="false"
PUBKEY_SIZE=0
GPG_OUTPUT=""
ARMOR_FOUND="false"

if [ -f "$PUBKEY_PATH" ]; then
    PUBKEY_EXISTS="true"
    PUBKEY_SIZE=$(stat -c %s "$PUBKEY_PATH" 2>/dev/null || echo "0")
    PUBKEY_MTIME=$(stat -c %Y "$PUBKEY_PATH" 2>/dev/null || echo "0")
    
    # Ensure it wasn't pre-existing
    if [ "$PUBKEY_MTIME" -gt "$TASK_START" ]; then
        PUBKEY_CREATED_DURING_TASK="true"
    fi
    
    # Check for valid PGP armor header
    if grep -q "\-\-\-\-\-BEGIN PGP PUBLIC KEY BLOCK\-\-\-\-\-" "$PUBKEY_PATH"; then
        ARMOR_FOUND="true"
    fi
    
    # Run gpg to check the key UID (suppress non-zero exit codes if invalid)
    GPG_OUTPUT=$(gpg --show-keys "$PUBKEY_PATH" 2>&1 || echo "GPG read failed")
fi

# 2. Extract application preferences safely
SIGN_MAIL="false"
OPENPGP_KEY_ID=""

if [ -f "$PREFS_FILE" ]; then
    # Make a temporary copy to avoid file lock issues with Thunderbird
    cp "$PREFS_FILE" /tmp/prefs_copy.js
    
    # Check if signing by default is enabled
    if grep -q "\"mail.identity.id1.sign_mail\", true" /tmp/prefs_copy.js; then
        SIGN_MAIL="true"
    fi
    
    # Check if an OpenPGP key ID is attached to the identity
    KEY_ID_LINE=$(grep "\"mail.identity.id1.openpgp_key_id\"" /tmp/prefs_copy.js || echo "")
    if [ -n "$KEY_ID_LINE" ]; then
        # Extract the key ID value inside the quotes
        OPENPGP_KEY_ID=$(echo "$KEY_ID_LINE" | sed -n 's/.*"mail.identity.id1.openpgp_key_id",[ \t]*"\(.*\)".*/\1/p')
    fi
fi

# 3. Create JSON payload using Python to avoid bash escaping hell
python3 << EOF
import json
data = {
    "task_start": int("$TASK_START"),
    "pubkey_exists": "$PUBKEY_EXISTS" == "true",
    "pubkey_created_during_task": "$PUBKEY_CREATED_DURING_TASK" == "true",
    "pubkey_size": int("$PUBKEY_SIZE"),
    "armor_found": "$ARMOR_FOUND" == "true",
    "gpg_output": """$GPG_OUTPUT""",
    "sign_mail": "$SIGN_MAIL" == "true",
    "openpgp_key_id": "$OPENPGP_KEY_ID"
}
with open("/tmp/task_result.json", "w") as f:
    json.dump(data, f)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="