#!/bin/bash
echo "=== Exporting edit_patient_record results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ─── Fetch Patient Record from CouchDB ─────────────────────────────────────
# We fetch directly from the database to verify the data was persisted.
DOC_URL="${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000002"
PATIENT_JSON=$(curl -s "$DOC_URL")

# Extract relevant fields using Python to handle JSON parsing reliably
# We extract BOTH the target fields (to check success) AND immutable fields (to check for corruption)
# and the _rev (to check for modification)
PYTHON_PARSER=$(cat <<EOF
import sys, json

try:
    raw = sys.stdin.read()
    if not raw:
        print(json.dumps({"error": "Empty response from CouchDB"}))
        sys.exit(0)
        
    doc = json.loads(raw)
    
    # Handle error response from CouchDB (e.g., {"error":"not_found" ...})
    if "error" in doc:
        print(json.dumps({"found": False, "error": doc.get("reason", "Unknown error")}))
        sys.exit(0)

    # HospitalRun structures data inside a 'data' key, but we handle flat too just in case
    data = doc.get("data", doc)
    
    result = {
        "found": True,
        "id": doc.get("_id"),
        "rev": doc.get("_rev"),
        # Target fields to verify
        "address": data.get("address", ""),
        "phone": data.get("phone", ""),
        "email": data.get("email", ""),
        # Immutable fields to verify identity preservation
        "firstName": data.get("firstName", ""),
        "lastName": data.get("lastName", ""),
        "dateOfBirth": data.get("dateOfBirth", ""),
        "sex": data.get("sex", ""),
        "bloodType": data.get("bloodType", "")
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF
)

PARSED_RESULT=$(echo "$PATIENT_JSON" | python3 -c "$PYTHON_PARSER")

# Save to temp file
echo "$PARSED_RESULT" > /tmp/parsed_patient.json

# ─── Construct Final Result JSON ───────────────────────────────────────────
# We combine the parsed DB result with environment metadata
# Using a temp file for the final JSON construction
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "db_result": $PARSED_RESULT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="