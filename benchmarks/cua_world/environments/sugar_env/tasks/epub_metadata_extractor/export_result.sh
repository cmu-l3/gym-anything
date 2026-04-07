#!/bin/bash
echo "=== Exporting epub_metadata_extractor task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/Documents/build_catalog.py"
OUTPUT_PATH="/home/ga/Documents/library_catalog.txt"

SCRIPT_EXISTS="false"
SCRIPT_USES_ZIPFILE="false"
INITIAL_OUTPUT_EXISTS="false"
INITIAL_OUTPUT_MODIFIED="false"
DYNAMIC_OUTPUT_EXISTS="false"

# 1. Analyze script
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if grep -q "zipfile" "$SCRIPT_PATH"; then
        SCRIPT_USES_ZIPFILE="true"
    fi
fi

# 2. Analyze initial output
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        INITIAL_OUTPUT_MODIFIED="true"
    fi
    # Capture initial content safely (up to 2KB)
    INITIAL_CONTENT=$(head -c 2000 "$OUTPUT_PATH" | tr -d '"\n\\' )
fi

# 3. Perform dynamic test (Anti-Gaming Check)
# This proves the script actually iterates files and parses them dynamically,
# rather than just hardcoding the output for the 3 initial books.
echo "Running dynamic test with hidden book..."

# Move the hidden book into the library
cp /var/lib/app/ground_truth/pg11.epub /home/ga/Documents/library/
chown ga:ga /home/ga/Documents/library/pg11.epub

# Delete the old output file
rm -f "$OUTPUT_PATH"

# Execute the agent's script as the user
if [ "$SCRIPT_EXISTS" = "true" ]; then
    su - ga -c "cd /home/ga/Documents && python3 $SCRIPT_PATH" > /tmp/dynamic_execution.log 2>&1
    
    if [ -f "$OUTPUT_PATH" ]; then
        DYNAMIC_OUTPUT_EXISTS="true"
        # Capture dynamic content safely
        DYNAMIC_CONTENT=$(head -c 2000 "$OUTPUT_PATH" | tr -d '"\n\\' )
    else
        DYNAMIC_CONTENT=""
    fi
else
    DYNAMIC_CONTENT=""
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/epub_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_uses_zipfile": $SCRIPT_USES_ZIPFILE,
    "initial_output_exists": $INITIAL_OUTPUT_EXISTS,
    "initial_output_modified": $INITIAL_OUTPUT_MODIFIED,
    "initial_content": "$INITIAL_CONTENT",
    "dynamic_output_exists": $DYNAMIC_OUTPUT_EXISTS,
    "dynamic_content": "$DYNAMIC_CONTENT"
}
EOF

# Move to final location
rm -f /tmp/epub_metadata_extractor_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/epub_metadata_extractor_result.json
chmod 666 /tmp/epub_metadata_extractor_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/epub_metadata_extractor_result.json"
echo "=== Export complete ==="