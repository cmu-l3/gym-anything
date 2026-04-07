#!/bin/bash
echo "=== Exporting fix_ical_parser result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/pycal_importer"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Public Tests (visible to agent)
echo "Running public tests..."
PUBLIC_TEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/test_parser.py -v --tb=short")
PUBLIC_EXIT_CODE=$?
PUBLIC_PASSED=$(echo "$PUBLIC_TEST_OUTPUT" | grep -c " PASSED" || true)

# 3. Run Hidden Stress Test (Verification)
# We generate this file NOW so the agent couldn't see it during the task.
# This tests edge cases combined: folded lines inside parameters, complex date formats, etc.
cat > /tmp/verify_hidden.py << 'EOF'
import sys
import os
sys.path.append("/home/ga/PycharmProjects/pycal_importer")

try:
    from pycal_importer.parser import parse_ics
    from pycal_importer.event import Event
except ImportError:
    print("IMPORT_ERROR")
    sys.exit(1)

# Complex ICS string:
# 1. Folded line in DESCRIPTION
# 2. Parameter in DTSTART
# 3. DATE-only format
# 4. Folded line in SUMMARY (less common but valid)
complex_ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Complicated
  Event
DTSTART;TZID=America/Los_Angeles:20231225T080000
DESCRIPTION:Line 1
 Line 2
DTEND;VALUE=DATE:20231226
END:VEVENT
END:VCALENDAR"""

try:
    events = parse_ics(complex_ics)
    if len(events) != 1:
        print(f"COUNT_FAIL: Expected 1 event, got {len(events)}")
        sys.exit(0)
        
    evt = events[0]
    results = []
    
    # Check Unfolding
    if evt.summary == "Complicated Event":
        results.append("UNFOLD_SUMMARY_PASS")
    else:
        results.append(f"UNFOLD_SUMMARY_FAIL: '{evt.summary}'")
        
    if evt.description == "Line 1 Line 2":
        results.append("UNFOLD_DESC_PASS")
    else:
        results.append(f"UNFOLD_DESC_FAIL: '{evt.description}'")

    # Check Params / Date Parsing
    if evt.start.year == 2023 and evt.start.hour == 8:
        results.append("DTSTART_PASS")
    else:
        results.append(f"DTSTART_FAIL: {evt.start}")

    # Check Date Only
    if evt.end and evt.end.year == 2023 and evt.end.day == 26:
        results.append("DTEND_PASS")
    else:
        results.append(f"DTEND_FAIL: {evt.end}")
        
    print("|".join(results))

except Exception as e:
    print(f"CRASH: {str(e)}")
EOF

echo "Running hidden verification..."
HIDDEN_OUTPUT=$(su - ga -c "python3 /tmp/verify_hidden.py")

# 4. Anti-gaming: Check if parser.py was modified
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$PROJECT_DIR/pycal_importer/parser.py" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
    FILE_MODIFIED="true"
fi

# 5. Construct JSON result
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/res.XXXXXX)

cat > "$TEMP_JSON" << EOF
{
    "public_tests_exit_code": $PUBLIC_EXIT_CODE,
    "public_tests_passed": $PUBLIC_PASSED,
    "hidden_output": "$(echo $HIDDEN_OUTPUT | sed 's/"/\\"/g')",
    "file_modified": $FILE_MODIFIED,
    "timestamp": $(date +%s)
}
EOF

mv "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE"

echo "=== Export complete ==="