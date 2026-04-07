#!/bin/bash
echo "=== Exporting discontinue_patient_medication result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve initial IDs safely
PID=$(python3 -c "import json; print(json.load(open('/tmp/initial_rx.json')).get('patient_id', ''))" 2>/dev/null)
TARGET_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_rx.json')).get('target_id', ''))" 2>/dev/null)
DISTRACTOR_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_rx.json')).get('distractor_id', ''))" 2>/dev/null)

# 1. Check state of Target (Atorvastatin)
TARGET_EXISTS_COUNT=$(freemed_query "SELECT COUNT(*) FROM rx WHERE id='$TARGET_ID'" 2>/dev/null || echo "0")
if [ "$TARGET_EXISTS_COUNT" -gt 0 ]; then
    TARGET_EXISTS="true"
    TARGET_NOTE=$(freemed_query "SELECT IFNULL(rxnote, '') FROM rx WHERE id='$TARGET_ID'" 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g' | sed "s/'/\\'/g")
else
    TARGET_EXISTS="false"
    TARGET_NOTE="DELETED"
fi

# 2. Check state of Distractor (Lisinopril)
DISTRACTOR_EXISTS_COUNT=$(freemed_query "SELECT COUNT(*) FROM rx WHERE id='$DISTRACTOR_ID'" 2>/dev/null || echo "0")
if [ "$DISTRACTOR_EXISTS_COUNT" -gt 0 ]; then
    DISTRACTOR_EXISTS="true"
    DISTRACTOR_NOTE=$(freemed_query "SELECT IFNULL(rxnote, '') FROM rx WHERE id='$DISTRACTOR_ID'" 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g' | sed "s/'/\\'/g")
else
    DISTRACTOR_EXISTS="false"
    DISTRACTOR_NOTE="DELETED"
fi

# 3. Check for any newly added prescriptions (in case they appended a new record instead of editing)
NEW_NOTES=$(freemed_query "SELECT GROUP_CONCAT(IFNULL(rxnote, '') SEPARATOR ' | ') FROM rx WHERE rxpatient='$PID' AND id NOT IN ('$TARGET_ID', '$DISTRACTOR_ID')" 2>/dev/null | tr -d '\n' | sed 's/"/\\"/g' | sed "s/'/\\'/g")

# Create JSON result securely via Python to handle edge cases in text formatting
python3 << EOF > /tmp/task_result.json
import json

data = {
    "target_exists": $TARGET_EXISTS,
    "target_note": "$TARGET_NOTE",
    "distractor_exists": $DISTRACTOR_EXISTS,
    "distractor_note": "$DISTRACTOR_NOTE",
    "new_notes": "$NEW_NOTES"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=4)
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Exported state:"
cat /tmp/task_result.json
echo "=== Export complete ==="