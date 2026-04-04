#!/bin/bash
echo "=== Exporting Conflict Check Result ==="

source /workspace/scripts/task_utils.sh

# ── 1. Load Task Data ────────────────────────────────────────────────────────
if [ -f /tmp/conflict_task_data.json ]; then
    OLD_CASE_ID=$(jq -r '.old_case_id' /tmp/conflict_task_data.json)
    NEW_CASE_ID=$(jq -r '.new_case_id' /tmp/conflict_task_data.json)
else
    echo "CRITICAL: Task data file missing!"
    OLD_CASE_ID=""
    NEW_CASE_ID=""
fi

echo "Checking New Case ($NEW_CASE_ID) for notes referencing Old Case ($OLD_CASE_ID)..."

# ── 2. Query ArkCase API for Notes ──────────────────────────────────────────
# We need to find the notes attached to the new case.
# Endpoints vary by configuration, but usually linked under the case ID.

# Fetch specific case details which often includes a 'notes' or 'comments' array
CASE_JSON=$(arkcase_api GET "plugin/complaint/${NEW_CASE_ID}" 2>/dev/null)

# Extract notes directly from case object if present
NOTES_TEXT=$(echo "$CASE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Check common fields for notes/comments
    notes = data.get('notes', []) or data.get('comments', [])
    # If it's a list of objects, join their text
    if isinstance(notes, list):
        print(' | '.join([str(n.get('text', '') or n.get('body', '') or n.get('note', '')) for n in notes]))
    else:
        print(str(notes))
except:
    print('')
")

# If notes weren't nested, try a dedicated notes endpoint
if [ -z "$NOTES_TEXT" ]; then
    NOTES_RESP=$(arkcase_api GET "plugin/complaint/${NEW_CASE_ID}/notes" 2>/dev/null)
    NOTES_TEXT=$(echo "$NOTES_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        print(' | '.join([str(n.get('text', '') or n.get('body', '')) for n in data]))
    else:
        print(str(data))
except:
    print('')
")
fi

echo "Captured Notes: $NOTES_TEXT"

# ── 3. Capture Final State ──────────────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 4. Generate Result JSON ─────────────────────────────────────────────────
# We handle permissions carefully using a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(date +%s),
    "old_case_id": "$OLD_CASE_ID",
    "new_case_id": "$NEW_CASE_ID",
    "extracted_notes": $(echo "$NOTES_TEXT" | jq -R .),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="