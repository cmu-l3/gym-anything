#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

# Load context
DEMO_NO=$(cat /tmp/task_demo_no 2>/dev/null || echo "0")
INITIAL_NOTE_ID=$(cat /tmp/task_note_id 2>/dev/null || echo "0")
TODAY=$(date +%Y-%m-%d)

echo "Checking notes for patient $DEMO_NO on $TODAY..."

# Query the database for the note
# We fetch the note with the specific ID we created, to see if it was updated in place
# We also fetch ANY note for today to see if a new one was created instead
NOTE_DATA_JSON=$(oscar_query "SELECT note_id, note, signed, observation_date FROM casemgmt_note WHERE demographic_no='$DEMO_NO' AND observation_date='$TODAY'" | \
    python3 -c "
import sys, json, csv
reader = csv.reader(sys.stdin, delimiter='\t')
notes = []
for row in reader:
    if len(row) >= 4:
        notes.append({
            'note_id': row[0],
            'note_content': row[1],
            'signed': row[2],
            'obs_date': row[3]
        })
print(json.dumps(notes))
")

echo "Notes found: $NOTE_DATA_JSON"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_note_id": "$INITIAL_NOTE_ID",
    "notes": $NOTE_DATA_JSON,
    "task_timestamp": "$(date -Iseconds)",
    "demo_no": "$DEMO_NO"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"