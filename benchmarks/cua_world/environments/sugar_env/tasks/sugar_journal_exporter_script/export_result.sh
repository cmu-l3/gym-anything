#!/bin/bash
echo "=== Exporting sugar_journal_exporter_script task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/journal_exporter_end.png" 2>/dev/null || true

# Script check
SCRIPT_PATH="/home/ga/Documents/journal_exporter.py"
SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
HAS_TRAVERSAL_LOGIC="false"
HAS_FILE_IO="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_PATH" 2>/dev/null || echo "0")
    
    if grep -q -E "os\.listdir|os\.walk|glob" "$SCRIPT_PATH"; then
        HAS_TRAVERSAL_LOGIC="true"
    fi
    if grep -q -E "shutil\.copy|open\(" "$SCRIPT_PATH"; then
        HAS_FILE_IO="true"
    fi
fi

# Output directory check
OUT_DIR="/home/ga/Documents/Exported_Logs"
DIR_EXISTS="false"
CH1_EXISTS="false"
CH2_EXISTS="false"
CH3_EXISTS="false"
FILES_HAVE_CONTENT="false"
DISTRACTOR_FILTERED="true"

if [ -d "$OUT_DIR" ]; then
    DIR_EXISTS="true"
    
    if [ -f "$OUT_DIR/Reading Log Chapter 1.txt" ]; then
        CH1_EXISTS="true"
        sz=$(stat --format=%s "$OUT_DIR/Reading Log Chapter 1.txt" 2>/dev/null || echo "0")
        if [ "$sz" -gt 10 ]; then FILES_HAVE_CONTENT="true"; fi
    fi
    
    if [ -f "$OUT_DIR/Reading Log Chapter 2.txt" ]; then
        CH2_EXISTS="true"
    fi
    
    if [ -f "$OUT_DIR/Reading Log Chapter 3.txt" ]; then
        CH3_EXISTS="true"
    fi
    
    # Check if White Rabbit Drawing was incorrectly exported
    if [ -f "$OUT_DIR/White Rabbit Drawing.txt" ] || [ -f "$OUT_DIR/White Rabbit Drawing.png" ] || [ -f "$OUT_DIR/White Rabbit Drawing" ]; then
        DISTRACTOR_FILTERED="false"
    fi
fi

cat > /tmp/journal_exporter_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "has_traversal_logic": $HAS_TRAVERSAL_LOGIC,
    "has_file_io": $HAS_FILE_IO,
    "dir_exists": $DIR_EXISTS,
    "ch1_exists": $CH1_EXISTS,
    "ch2_exists": $CH2_EXISTS,
    "ch3_exists": $CH3_EXISTS,
    "files_have_content": $FILES_HAVE_CONTENT,
    "distractor_filtered": $DISTRACTOR_FILTERED
}
EOF

chmod 666 /tmp/journal_exporter_result.json
echo "Result saved to /tmp/journal_exporter_result.json"
cat /tmp/journal_exporter_result.json
echo "=== Export complete ==="