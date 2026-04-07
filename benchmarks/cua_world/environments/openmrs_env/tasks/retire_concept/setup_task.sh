#!/bin/bash
set -e
echo "=== Setting up retire_concept task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ── 1. Helper to find Metadata UUIDs ──────────────────────────────────────────
# We need valid UUIDs for Concept Class (Misc) and Datatype (N/A) to create the concept
echo "Resolving metadata UUIDs..."
CLASS_UUID=$(omrs_get "/conceptclass?q=Misc&v=default" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '8d4918b0-c2cc-11de-8d13-0010c6dffd0f')")
DATATYPE_UUID=$(omrs_get "/conceptdatatype?q=N/A&v=default" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '8d4a4c94-c2cc-11de-8d13-0010c6dffd0f')")

# ── 2. Create or Reset the Concept ────────────────────────────────────────────
CONCEPT_NAME="Legacy Pain Management"
echo "Ensuring concept '$CONCEPT_NAME' exists and is active..."

# Check if exists
EXISTING=$(omrs_get "/concept?q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$CONCEPT_NAME'))")&v=default")
EXISTING_UUID=$(echo "$EXISTING" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')")

if [ -n "$EXISTING_UUID" ]; then
    echo "Concept exists ($EXISTING_UUID). Resetting state..."
    # Force un-retire via DB to ensure clean state
    omrs_db_query "UPDATE concept SET retired = 0, retire_reason = NULL, retired_by = NULL, date_retired = NULL WHERE uuid = '$EXISTING_UUID';"
else
    echo "Creating new concept..."
    PAYLOAD=$(cat <<EOF
{
  "names": [
    {
      "name": "$CONCEPT_NAME",
      "locale": "en",
      "conceptNameType": "FULLY_SPECIFIED"
    }
  ],
  "datatype": "$DATATYPE_UUID",
  "conceptClass": "$CLASS_UUID",
  "version": "1.0"
}
EOF
)
    RESP=$(omrs_post "/concept" "$PAYLOAD")
    EXISTING_UUID=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    
    if [ -z "$EXISTING_UUID" ]; then
        echo "ERROR: Failed to create concept. Response: $RESP"
        # Try a fallback DB insertion if REST fails (unlikely but safe)
        exit 1
    fi
fi

echo "Target Concept UUID: $EXISTING_UUID"
echo "$EXISTING_UUID" > /tmp/target_concept_uuid.txt

# ── 3. Start Browser ──────────────────────────────────────────────────────────
# Navigate to Legacy Admin page, as this is where Dictionary management usually happens
ADMIN_URL="http://localhost/openmrs/openmrs/admin/index.htm"
echo "Launching browser at $ADMIN_URL..."

ensure_openmrs_logged_in "$ADMIN_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="