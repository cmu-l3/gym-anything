#!/bin/bash
echo "=== Exporting Piano Keyboard Diagram result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Define expected paths
EXPECTED_FILE="/home/ga/Documents/Flipcharts/piano_keyboard.flipchart"
EXPECTED_FILE_ALT="/home/ga/Documents/Flipcharts/piano_keyboard.flp"

# Initialize variables
FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MTIME=0
FILE_VALID="false"
CREATED_DURING_TASK="false"
RECTANGLE_COUNT=0
BLACK_FILL_FOUND="false"
TEXT_FOUND_FLAGS=""

# Check if file exists
if [ -f "$EXPECTED_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE"
elif [ -f "$EXPECTED_FILE_ALT" ]; then
    FILE_FOUND="true"
    FILE_PATH="$EXPECTED_FILE_ALT"
fi

if [ "$FILE_FOUND" = "true" ]; then
    FILE_SIZE=$(get_file_size "$FILE_PATH")
    FILE_MTIME=$(get_file_mtime "$FILE_PATH")
    
    # Verify creation time
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check validity and analyze content
    if check_flipchart_file "$FILE_PATH" | grep -q "valid"; then
        FILE_VALID="true"
        
        # Extract content to temp dir
        TEMP_DIR=$(mktemp -d)
        if unzip -q "$FILE_PATH" -d "$TEMP_DIR" 2>/dev/null; then
            
            # 1. Count Rectangles
            # Look for shape definitions in XML. 
            # ActivInspire often uses <AsRectangle> or type="Rectangle"
            # We look in all XML files (page content is usually in pageXXX.xml)
            RECTANGLE_COUNT=$(grep -rE '<[Aa]s[Rr]ectangle|type="[Rr]ectangle"|shapeType="[Rr]ectangle"' "$TEMP_DIR" | wc -l)
            
            # 2. Check for Black Fill
            # Black color is often represented as ARGB decimal 4278190080 (Opacity 255, R0, G0, B0)
            # or Hex #FF000000. Sometimes just "Black" in some contexts.
            # We'll check for "Black" or common zero-value RGB indicators if possible, 
            # but relying on VLM for strict visual color check is safer.
            # However, we can check if *any* shapes have different properties to imply white/black distinction.
            # Let's simple grep for potential black definitions.
            if grep -rqE 'color="Black"|value="4278190080"|#000000|#FF000000' "$TEMP_DIR"; then
                BLACK_FILL_FOUND="true"
            fi
            
            # 3. Check Text Content
            # Combine all XML text content
            ALL_TEXT=$(grep -rh "<" "$TEMP_DIR" | tr -d '\n' 2>/dev/null)
            
            # Helper to check string presence
            check_text() {
                if echo "$ALL_TEXT" | grep -qi "$1"; then echo "1"; else echo "0"; fi
            }
            
            T_TITLE=$(check_text "Piano Keys")
            T_C=$(check_text ">C<") # Brackets to avoid matching 'C' inside other words
            T_D=$(check_text ">D<")
            T_E=$(check_text ">E<")
            T_F=$(check_text ">F<")
            T_G=$(check_text ">G<")
            T_A=$(check_text ">A<")
            T_B=$(check_text ">B<")
            
            # If explicit tags like >C< fail (formatting might split tags), try simpler search
            if [ "$T_C" -eq 0 ]; then T_C=$(check_text "C"); fi
            if [ "$T_D" -eq 0 ]; then T_D=$(check_text "D"); fi
            if [ "$T_E" -eq 0 ]; then T_E=$(check_text "E"); fi
            if [ "$T_F" -eq 0 ]; then T_F=$(check_text "F"); fi
            if [ "$T_G" -eq 0 ]; then T_G=$(check_text "G"); fi
            if [ "$T_A" -eq 0 ]; then T_A=$(check_text "A"); fi
            if [ "$T_B" -eq 0 ]; then T_B=$(check_text "B"); fi
            
            TEXT_FOUND_FLAGS="${T_TITLE},${T_C},${T_D},${T_E},${T_F},${T_G},${T_A},${T_B}"
        fi
        rm -rf "$TEMP_DIR"
    fi
fi

# Create JSON result
create_result_json << EOF
{
    "file_found": $(json_bool "$FILE_FOUND"),
    "file_path": "$FILE_PATH",
    "file_size": ${FILE_SIZE:-0},
    "file_valid": $(json_bool "$FILE_VALID"),
    "created_during_task": $(json_bool "$CREATED_DURING_TASK"),
    "rectangle_count": ${RECTANGLE_COUNT:-0},
    "black_fill_detected": $(json_bool "$BLACK_FILL_FOUND"),
    "text_flags": "$TEXT_FOUND_FLAGS",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="