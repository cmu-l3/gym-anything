#!/bin/bash
echo "=== Exporting generate_naca_airfoil result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check primary expected output location
OUTPUT_FILE="/home/ga/Documents/airfoils/generated_naca4412.dat"
FILE_EXISTS="false"
FILE_LINES=0
HAS_COORDINATES="false"
LOOKS_LIKE_NACA="false"
HEADER_HAS_4412="false"
IS_COPY="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_LINES=$(wc -l < "$OUTPUT_FILE")

    # Check if file contains coordinate data (numbers in two columns)
    COORD_LINES=$(grep -cE '^[[:space:]]*-?[0-9]+\.[0-9]+[[:space:]]+-?[0-9]+\.[0-9]+' "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$COORD_LINES" -gt 5 ]; then
        HAS_COORDINATES="true"
    fi

    # Check if file header mentions NACA
    if grep -qi "naca" "$OUTPUT_FILE" 2>/dev/null; then
        LOOKS_LIKE_NACA="true"
    fi

    # Check specifically for "4412" in the first line (header)
    FIRST_LINE=$(head -1 "$OUTPUT_FILE" 2>/dev/null)
    if echo "$FIRST_LINE" | grep -q "4412" 2>/dev/null; then
        HEADER_HAS_4412="true"
    fi

    # Anti-copy check: compare against pre-existing naca4412.dat
    PREEXISTING="/home/ga/Documents/airfoils/naca4412.dat"
    if [ -f "$PREEXISTING" ]; then
        GEN_HASH=$(md5sum "$OUTPUT_FILE" 2>/dev/null | awk '{print $1}')
        PRE_HASH=$(md5sum "$PREEXISTING" 2>/dev/null | awk '{print $1}')
        if [ "$GEN_HASH" = "$PRE_HASH" ]; then
            IS_COPY="true"
        fi
        # Also check: if line counts match the pre-existing file exactly
        PRE_LINES=$(wc -l < "$PREEXISTING" 2>/dev/null || echo "0")
        if [ "$FILE_LINES" = "$PRE_LINES" ] && [ "$FILE_LINES" -lt 50 ]; then
            IS_COPY="true"
        fi
    fi
fi

QBLADE_RUNNING=$(is_qblade_running)

RESULT_JSON=$(cat << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_lines": $FILE_LINES,
    "has_coordinates": $HAS_COORDINATES,
    "looks_like_naca": $LOOKS_LIKE_NACA,
    "header_has_4412": $HEADER_HAS_4412,
    "is_copy_of_existing": $IS_COPY,
    "qblade_running": $([ "$QBLADE_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$RESULT_JSON"

echo "=== Export complete ==="
