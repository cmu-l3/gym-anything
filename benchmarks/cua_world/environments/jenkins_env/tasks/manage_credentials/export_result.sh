#!/bin/bash
# Export script for Manage Credentials task
# Checks if the expected credential was added to Jenkins

echo "=== Exporting Manage Credentials Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

EXPECTED_ID="deploy-credentials"
EXPECTED_USERNAME="deploy-user"
CREDENTIAL_FOUND="false"
CREDENTIAL_ID=""
CREDENTIAL_TYPE=""
CREDENTIAL_USERNAME=""
CREDENTIAL_DESCRIPTION=""
CURRENT_COUNT=0

# Get all credentials from the global domain
echo "Querying Jenkins credentials API..."
CREDS_JSON=$(jenkins_api "credentials/store/system/domain/_/api/json?depth=2" 2>/dev/null)

if [ -n "$CREDS_JSON" ]; then
    CURRENT_COUNT=$(echo "$CREDS_JSON" | jq '.credentials | length' 2>/dev/null || echo "0")
    echo "Current credential count: $CURRENT_COUNT"

    # Search for expected credential by ID
    CRED_MATCH=$(echo "$CREDS_JSON" | jq -r ".credentials[] | select(.id == \"$EXPECTED_ID\")" 2>/dev/null)

    if [ -n "$CRED_MATCH" ]; then
        CREDENTIAL_FOUND="true"
        CREDENTIAL_ID=$(echo "$CRED_MATCH" | jq -r '.id // empty' 2>/dev/null)
        CREDENTIAL_TYPE=$(echo "$CRED_MATCH" | jq -r '._class // empty' 2>/dev/null)
        CREDENTIAL_DESCRIPTION=$(echo "$CRED_MATCH" | jq -r '.description // empty' 2>/dev/null)
        echo "Found credential by ID: $CREDENTIAL_ID"
    else
        # Fallback: search by description
        CRED_MATCH=$(echo "$CREDS_JSON" | jq -r '.credentials[] | select(.description | test("deploy"; "i"))' 2>/dev/null)
        if [ -n "$CRED_MATCH" ]; then
            CREDENTIAL_FOUND="true"
            CREDENTIAL_ID=$(echo "$CRED_MATCH" | jq -r '.id // empty' 2>/dev/null)
            CREDENTIAL_TYPE=$(echo "$CRED_MATCH" | jq -r '._class // empty' 2>/dev/null)
            CREDENTIAL_DESCRIPTION=$(echo "$CRED_MATCH" | jq -r '.description // empty' 2>/dev/null)
            echo "Found credential by description: $CREDENTIAL_DESCRIPTION"
        fi
    fi

    # Try to get the username via the credential's specific API
    if [ "$CREDENTIAL_FOUND" = "true" ] && [ -n "$CREDENTIAL_ID" ]; then
        CRED_DETAIL=$(jenkins_api "credentials/store/system/domain/_/credential/$CREDENTIAL_ID/api/json?depth=1" 2>/dev/null)
        if [ -n "$CRED_DETAIL" ]; then
            CREDENTIAL_USERNAME=$(echo "$CRED_DETAIL" | jq -r '.username // empty' 2>/dev/null)
            if [ -z "$CREDENTIAL_USERNAME" ]; then
                # Some credential types expose username differently
                CREDENTIAL_USERNAME=$(echo "$CRED_DETAIL" | jq -r '.displayName // empty' 2>/dev/null)
            fi
            echo "Credential username: $CREDENTIAL_USERNAME"
        fi
    fi
else
    echo "WARNING: Could not query credentials API"
fi

INITIAL_COUNT=$(cat /tmp/initial_credential_count 2>/dev/null || echo "0")

# Create JSON using jq
TEMP_JSON=$(mktemp /tmp/manage_credentials_result.XXXXXX.json)
jq -n \
    --argjson credential_found "$CREDENTIAL_FOUND" \
    --arg credential_id "$CREDENTIAL_ID" \
    --arg credential_type "$CREDENTIAL_TYPE" \
    --arg credential_username "$CREDENTIAL_USERNAME" \
    --arg credential_description "$CREDENTIAL_DESCRIPTION" \
    --argjson initial_count "${INITIAL_COUNT:-0}" \
    --argjson current_count "${CURRENT_COUNT:-0}" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        credential_found: $credential_found,
        credential: {
            id: $credential_id,
            type: $credential_type,
            username: $credential_username,
            description: $credential_description
        },
        initial_credential_count: $initial_count,
        current_credential_count: $current_count,
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

rm -f /tmp/manage_credentials_result.json 2>/dev/null || sudo rm -f /tmp/manage_credentials_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/manage_credentials_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/manage_credentials_result.json
chmod 666 /tmp/manage_credentials_result.json 2>/dev/null || sudo chmod 666 /tmp/manage_credentials_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/manage_credentials_result.json"
cat /tmp/manage_credentials_result.json

echo ""
echo "=== Export Complete ==="
