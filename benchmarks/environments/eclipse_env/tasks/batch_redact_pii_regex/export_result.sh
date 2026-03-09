#!/bin/bash
echo "=== Exporting batch_redact_pii_regex result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/PatientConnector"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Counters
TOTAL_SSN_REMAINING=0
TOTAL_MRN_REMAINING=0
TOTAL_SSN_REDACTED=0
TOTAL_MRN_REDACTED=0
FILES_CHECKED=0

# Define Regex Patterns (PCRE)
# SSN: 3 digits, hyphen, 2 digits, hyphen, 4 digits. Avoid matching placeholders.
SSN_REGEX="\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b"
# MRN: MRN- followed by 6 digits. Avoid matching MRN-000000.
MRN_REGEX="MRN-[1-9][0-9]{5}|MRN-0[0-9]{5}|MRN-[0-9]{1,5}[1-9]" # Tricky to regex "not 000000", simpler to grep for digits and exclude specific string

# Redacted patterns
REDACTED_SSN_STR="XXX-XX-XXXX"
REDACTED_MRN_STR="MRN-000000"

echo "Scanning files in $PROJECT_DIR..."

# Use grep to count occurrences
# recursively search the project directory
# We exclude the .git and bin directories if they exist

# 1. Count Remaining Real SSNs
# We search for the pattern, then exclude the redacted string to be safe (though regex shouldn't match X)
SSN_MATCHES=$(grep -rE "$SSN_REGEX" "$PROJECT_DIR" | grep -v "$REDACTED_SSN_STR" | wc -l)
TOTAL_SSN_REMAINING=$SSN_MATCHES

# 2. Count Remaining Real MRNs
# We search for MRN-digits, then exclude MRN-000000
MRN_MATCHES=$(grep -rE "MRN-[0-9]{6}" "$PROJECT_DIR" | grep -v "MRN-000000" | wc -l)
TOTAL_MRN_REMAINING=$MRN_MATCHES

# 3. Count Redacted SSNs
SSN_REDACTED_MATCHES=$(grep -rF "$REDACTED_SSN_STR" "$PROJECT_DIR" | wc -l)
TOTAL_SSN_REDACTED=$SSN_REDACTED_MATCHES

# 4. Count Redacted MRNs
MRN_REDACTED_MATCHES=$(grep -rF "$REDACTED_MRN_STR" "$PROJECT_DIR" | wc -l)
TOTAL_MRN_REDACTED=$MRN_REDACTED_MATCHES

# 5. Check File Integrity (Did they delete files?)
FILES_EXIST="true"
if [ ! -f "$PROJECT_DIR/src/main/java/com/medsoft/connector/TestPatient.java" ] || \
   [ ! -f "$PROJECT_DIR/src/main/resources/import_batch.xml" ] || \
   [ ! -f "$PROJECT_DIR/logs/server.log" ]; then
    FILES_EXIST="false"
fi

# 6. Check if Eclipse is running
APP_RUNNING="false"
if pgrep -f "eclipse" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON Result
cat > "$RESULT_FILE" <<EOF
{
    "ssn_remaining": $TOTAL_SSN_REMAINING,
    "mrn_remaining": $TOTAL_MRN_REMAINING,
    "ssn_redacted": $TOTAL_SSN_REDACTED,
    "mrn_redacted": $TOTAL_MRN_REDACTED,
    "files_exist": $FILES_EXIST,
    "app_running": $APP_RUNNING,
    "timestamp": $(date +%s)
}
EOF

# Set permissions
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="