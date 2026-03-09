#!/bin/bash
echo "=== Exporting reading_readiness_assessment result ==="

source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/Desktop/reading_readiness_report.txt"
TASK_START=$(cat /tmp/task_start_ts_reading_readiness 2>/dev/null || echo "0")

take_screenshot /tmp/reading_readiness_end.png

REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# Check for section and activity keywords
HAS_LETTERS=0
HAS_WORDS=0
HAS_VOCABULARY=0
HAS_ALPHABET=0
HAS_KEYBOARD=0
HAS_UPPERCASE=0
HAS_LOWERCASE=0
HAS_WORD_PROCESSOR=0
HAS_TYPING=0

if [ "$REPORT_EXISTS" = "true" ]; then
    grep -qi "letters\b\|letters section\|letters tab" "$REPORT_FILE" 2>/dev/null && HAS_LETTERS=1
    grep -qi "\bwords\b\|words section\|words tab" "$REPORT_FILE" 2>/dev/null && HAS_WORDS=1
    grep -qi "vocabulary\|vocab" "$REPORT_FILE" 2>/dev/null && HAS_VOCABULARY=1
    grep -qi "alphabet" "$REPORT_FILE" 2>/dev/null && HAS_ALPHABET=1
    grep -qi "keyboard" "$REPORT_FILE" 2>/dev/null && HAS_KEYBOARD=1
    grep -qi "uppercase\|upper.case\|upper case" "$REPORT_FILE" 2>/dev/null && HAS_UPPERCASE=1
    grep -qi "lowercase\|lower.case\|lower case" "$REPORT_FILE" 2>/dev/null && HAS_LOWERCASE=1
    grep -qi "word.processor\|wordprocessor" "$REPORT_FILE" 2>/dev/null && HAS_WORD_PROCESSOR=1
    grep -qi "typing\|type letters\|type words" "$REPORT_FILE" 2>/dev/null && HAS_TYPING=1
fi

python3 << PYEOF
import json

task_start = int("$TASK_START")
report_mtime = int("$REPORT_MTIME")

result = {
    "task_start": task_start,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size": int("$REPORT_SIZE"),
    "report_modified_after_start": int(report_mtime) > task_start,
    "has_letters_section": $HAS_LETTERS == 1,
    "has_words_section": $HAS_WORDS == 1,
    "has_vocabulary_section": $HAS_VOCABULARY == 1,
    "has_alphabet_keyword": $HAS_ALPHABET == 1,
    "has_keyboard_keyword": $HAS_KEYBOARD == 1,
    "has_uppercase_keyword": $HAS_UPPERCASE == 1,
    "has_lowercase_keyword": $HAS_LOWERCASE == 1,
    "has_word_processor_keyword": $HAS_WORD_PROCESSOR == 1,
    "has_typing_keyword": $HAS_TYPING == 1,
}

with open("/tmp/reading_readiness_assessment_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/reading_readiness_assessment_result.json")
PYEOF

echo "=== Export complete ==="
