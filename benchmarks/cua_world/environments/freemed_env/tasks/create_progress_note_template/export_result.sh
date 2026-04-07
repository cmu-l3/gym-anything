#!/bin/bash
# Export script for create_progress_note_template task

echo "=== Exporting Create Progress Note Template Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Dump the final database state to check for the new template data
echo "Dumping final database state..."
mysqldump -u freemed -pfreemed freemed > /tmp/final_dump.sql 2>/dev/null || true

# Count occurrences of the expected phrases in the final database state
FINAL_TITLE=$(grep -ci "Normal Physical Exam" /tmp/final_dump.sql 2>/dev/null || echo "0")
FINAL_PHRASE1=$(grep -ci "in no acute distress" /tmp/final_dump.sql 2>/dev/null || echo "0")
FINAL_PHRASE2=$(grep -ci "No murmurs, rubs, or gallops" /tmp/final_dump.sql 2>/dev/null || echo "0")
FINAL_PHRASE3=$(grep -ci "clear to auscultation bilaterally" /tmp/final_dump.sql 2>/dev/null || echo "0")

# Retrieve initial counts
INIT_TITLE=$(cat /tmp/init_count_title.txt 2>/dev/null || echo "0")
INIT_PHRASE1=$(cat /tmp/init_count_phrase1.txt 2>/dev/null || echo "0")
INIT_PHRASE2=$(cat /tmp/init_count_phrase2.txt 2>/dev/null || echo "0")
INIT_PHRASE3=$(cat /tmp/init_count_phrase3.txt 2>/dev/null || echo "0")

echo "Title Count: $INIT_TITLE -> $FINAL_TITLE"
echo "Phrase 1 Count: $INIT_PHRASE1 -> $FINAL_PHRASE1"
echo "Phrase 2 Count: $INIT_PHRASE2 -> $FINAL_PHRASE2"
echo "Phrase 3 Count: $INIT_PHRASE3 -> $FINAL_PHRASE3"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/template_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "init_title_count": $INIT_TITLE,
    "final_title_count": $FINAL_TITLE,
    "init_phrase1_count": $INIT_PHRASE1,
    "final_phrase1_count": $FINAL_PHRASE1,
    "init_phrase2_count": $INIT_PHRASE2,
    "final_phrase2_count": $FINAL_PHRASE2,
    "init_phrase3_count": $INIT_PHRASE3,
    "final_phrase3_count": $FINAL_PHRASE3,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="