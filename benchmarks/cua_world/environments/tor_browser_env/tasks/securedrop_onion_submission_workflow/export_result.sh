#!/bin/bash
# export_result.sh for securedrop_onion_submission_workflow
# Evaluates Tor Browser history, the agent's GPG keyring, and server submissions.

echo "=== Exporting securedrop_onion_submission_workflow results ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Tor Browser History
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

ONION_VISITED="false"
if [ -n "$PROFILE_DIR" ]; then
    TEMP_DB="/tmp/places_export.sqlite"
    cp "$PROFILE_DIR/places.sqlite" "$TEMP_DB" 2>/dev/null || true
    
    ONION_URL=$(cat /home/ga/Desktop/securedrop_address.txt 2>/dev/null | awk -F/ '{print $3}')
    
    if [ -n "$ONION_URL" ] && [ -f "$TEMP_DB" ]; then
        VISIT_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM moz_places WHERE url LIKE '%$ONION_URL%';" 2>/dev/null || echo "0")
        if [ "$VISIT_COUNT" -gt 0 ]; then
            ONION_VISITED="true"
        fi
    fi
    rm -f "$TEMP_DB"
fi

# 2. Check User's GPG Keyring
GPG_KEY_IMPORTED="false"
if sudo -u ga gpg --list-keys "secure@drop.local" >/dev/null 2>&1; then
    GPG_KEY_IMPORTED="true"
fi

# 3. Check Submissions received by mock server
SUBMISSION_EXISTS="false"
VALID_PGP="false"
DECRYPTION_SUCCESSFUL="false"
MATCHES_EVIDENCE="false"

LATEST_SUB=$(ls -t /tmp/securedrop_submissions/sub_*.txt 2>/dev/null | head -1 || echo "")

if [ -n "$LATEST_SUB" ]; then
    SUBMISSION_EXISTS="true"
    
    # Check if content looks like a PGP message
    if grep -q "BEGIN PGP MESSAGE" "$LATEST_SUB"; then
        VALID_PGP="true"
        
        # Use server's private key to decrypt the submission
        export GNUPGHOME=/tmp/securedrop_mock
        DECRYPTED=$(gpg --batch --yes --decrypt "$LATEST_SUB" 2>/dev/null || echo "")
        
        if [ -n "$DECRYPTED" ]; then
            DECRYPTION_SUCCESSFUL="true"
            
            # Compare decrypted content to ground truth
            EVIDENCE_TEXT=$(cat /home/ga/Documents/evidence_tip.txt 2>/dev/null || echo "")
            
            # Remove all whitespace/newlines for robust comparison
            DEC_CLEAN=$(echo "$DECRYPTED" | tr -d ' \t\n\r')
            EVI_CLEAN=$(echo "$EVIDENCE_TEXT" | tr -d ' \t\n\r')
            
            if [ "$DEC_CLEAN" = "$EVI_CLEAN" ]; then
                MATCHES_EVIDENCE="true"
            fi
        fi
    fi
fi

# 4. Generate JSON Output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "onion_visited": $ONION_VISITED,
    "gpg_key_imported": $GPG_KEY_IMPORTED,
    "submission_exists": $SUBMISSION_EXISTS,
    "valid_pgp": $VALID_PGP,
    "decryption_successful": $DECRYPTION_SUCCESSFUL,
    "matches_evidence": $MATCHES_EVIDENCE,
    "timestamp": $(date +%s)
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="