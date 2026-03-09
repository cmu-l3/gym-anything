#!/bin/bash
echo "=== Exporting design_contractor_badge result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task timestamps
TASK_START=$(cat /tmp/design_contractor_badge_start_time 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# ==============================================================================
# Search for the created file
# ==============================================================================
TARGET_NAME="Contractor_Badge"
FOUND_FILE=""
FILE_SIZE=0
FILE_MTIME=0

# Search recursively in ga's home directory for the file, ignoring case
# We expect extensions like .btf, .bdg, .xml, etc.
echo "Searching for $TARGET_NAME..."
FOUND_PATHS=$(find /home/ga -type f -iname "${TARGET_NAME}.*" -not -path "*/.*" 2>/dev/null)

if [ -n "$FOUND_PATHS" ]; then
    # Pick the most recently modified one if multiple exist
    FOUND_FILE=$(ls -t $FOUND_PATHS | head -1)
    echo "Found candidate file: $FOUND_FILE"
    
    FILE_SIZE=$(stat -c%s "$FOUND_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$FOUND_FILE" 2>/dev/null || echo "0")
else
    echo "No file named $TARGET_NAME found."
fi

# ==============================================================================
# Content Analysis (String Search)
# ==============================================================================
# Lobby Track templates might be binary or XML. We use 'strings' or 'grep -a' to find text.
# We look for:
# 1. "CONTRACTOR" (The specific title requested)
# 2. Field binding traces (Name, Company, Date)

HAS_TITLE="false"
HAS_NAME="false"
HAS_COMPANY="false"
HAS_DATE="false"

if [ -n "$FOUND_FILE" ]; then
    # Create a text dump of the file for searching
    strings "$FOUND_FILE" > /tmp/file_strings.txt 2>/dev/null || cat "$FOUND_FILE" > /tmp/file_strings.txt

    if grep -qi "CONTRACTOR" /tmp/file_strings.txt; then
        HAS_TITLE="true"
    fi

    # Check for fields - logic might match "Visitor.Name", "Field:Name", etc.
    if grep -qi "Name" /tmp/file_strings.txt; then
        HAS_NAME="true"
    fi

    if grep -qi "Company" /tmp/file_strings.txt; then
        HAS_COMPANY="true"
    fi

    if grep -qi "Date" /tmp/file_strings.txt || grep -qi "Time" /tmp/file_strings.txt; then
        HAS_DATE="true"
    fi
fi

# ==============================================================================
# Export JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "current_time": $CURRENT_TIME,
    "found_file_path": "$FOUND_FILE",
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "content_check": {
        "has_title_contractor": $HAS_TITLE,
        "has_field_name": $HAS_NAME,
        "has_field_company": $HAS_COMPANY,
        "has_field_date": $HAS_DATE
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="