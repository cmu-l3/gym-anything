#!/bin/bash
# Export script for Add Provider task
# Queries the OSCAR database to verify if the provider and security records were created correctly.

echo "=== Exporting Add Provider Result ==="

source /workspace/scripts/task_utils.sh

# 1. CAPTURE EVIDENCE
# Take final screenshot of the UI
take_screenshot /tmp/task_final_screenshot.png

# 2. QUERY PROVIDER DATA
# We specifically look for the provider number 100123
echo "Querying provider table..."
PROVIDER_DATA=$(oscar_query "SELECT provider_no, last_name, first_name, provider_type, specialty, sex, work_phone, status FROM provider WHERE provider_no='100123' LIMIT 1" 2>/dev/null)

# Parse Provider Data (Tab separated)
P_EXISTS="false"
P_NO=""
P_LNAME=""
P_FNAME=""
P_TYPE=""
P_SPEC=""
P_SEX=""
P_PHONE=""
P_STATUS=""

if [ -n "$PROVIDER_DATA" ]; then
    P_EXISTS="true"
    P_NO=$(echo "$PROVIDER_DATA" | cut -f1)
    P_LNAME=$(echo "$PROVIDER_DATA" | cut -f2)
    P_FNAME=$(echo "$PROVIDER_DATA" | cut -f3)
    P_TYPE=$(echo "$PROVIDER_DATA" | cut -f4)
    P_SPEC=$(echo "$PROVIDER_DATA" | cut -f5)
    P_SEX=$(echo "$PROVIDER_DATA" | cut -f6)
    P_PHONE=$(echo "$PROVIDER_DATA" | cut -f7)
    P_STATUS=$(echo "$PROVIDER_DATA" | cut -f8)
fi

# 3. QUERY SECURITY DATA
# We look for username 'ewatson'
echo "Querying security table..."
SECURITY_DATA=$(oscar_query "SELECT user_name, provider_no, pin FROM security WHERE user_name='ewatson' LIMIT 1" 2>/dev/null)

# Parse Security Data
S_EXISTS="false"
S_USER=""
S_LINK_NO=""
S_PIN=""

if [ -n "$SECURITY_DATA" ]; then
    S_EXISTS="true"
    S_USER=$(echo "$SECURITY_DATA" | cut -f1)
    S_LINK_NO=$(echo "$SECURITY_DATA" | cut -f2)
    S_PIN=$(echo "$SECURITY_DATA" | cut -f3)
fi

# 4. JSON EXPORT
# Create the result JSON file for the python verifier
TEMP_JSON=$(mktemp /tmp/add_provider_result.XXXXXX.json)

# Use jq if available for safe JSON creation, otherwise cat with manual escaping
# Since minimal environment, we use cat and carefully format.
# Note: Python verifier handles type conversion, we output strings/bools.

cat > "$TEMP_JSON" << EOF
{
    "provider_record": {
        "exists": $P_EXISTS,
        "provider_no": "$P_NO",
        "last_name": "$P_LNAME",
        "first_name": "$P_FNAME",
        "type": "$P_TYPE",
        "specialty": "$P_SPEC",
        "sex": "$P_SEX",
        "phone": "$P_PHONE",
        "status": "$P_STATUS"
    },
    "security_record": {
        "exists": $S_EXISTS,
        "username": "$S_USER",
        "linked_provider_no": "$S_LINK_NO",
        "pin": "$S_PIN"
    },
    "counts": {
        "initial_provider": $(cat /tmp/initial_provider_count 2>/dev/null || echo 0),
        "initial_security": $(cat /tmp/initial_security_count 2>/dev/null || echo 0),
        "final_provider": $(oscar_query "SELECT COUNT(*) FROM provider" || echo 0),
        "final_security": $(oscar_query "SELECT COUNT(*) FROM security" || echo 0)
    },
    "timestamp": "$(date +%s)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="