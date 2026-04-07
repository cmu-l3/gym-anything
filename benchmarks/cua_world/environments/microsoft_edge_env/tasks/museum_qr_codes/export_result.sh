#!/bin/bash
# export_result.sh - Post-task hook for museum_qr_codes
set -e

echo "=== Exporting Museum QR Codes Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DESKTOP_DIR="/home/ga/Desktop"
MANIFEST_PATH="$DESKTOP_DIR/qr_manifest.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define targets
declare -A TARGETS
TARGETS["eniac"]="eniac_qr.png"
TARGETS["hopper"]="hopper_qr.png"
TARGETS["transistor"]="transistor_qr.png"

# Prepare result JSON structure
TEMP_JSON=$(mktemp /tmp/qr_result.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"files\": {" >> "$TEMP_JSON"

# Iterate through expected files and verify them
FIRST=true
for KEY in "${!TARGETS[@]}"; do
    FILENAME="${TARGETS[$KEY]}"
    FILEPATH="$DESKTOP_DIR/$FILENAME"
    
    EXISTS="false"
    CREATED_DURING_TASK="false"
    VALID_IMAGE="false"
    DECODED_URL=""
    
    if [ -f "$FILEPATH" ]; then
        EXISTS="true"
        MTIME=$(stat -c %Y "$FILEPATH")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
        
        # Check if valid image and decode QR
        if zbarimg --raw -q "$FILEPATH" > /tmp/qr_decode.txt 2>/dev/null; then
            VALID_IMAGE="true"
            DECODED_URL=$(cat /tmp/qr_decode.txt)
        else
            # Try valid image check even if not a QR code
            if file "$FILEPATH" | grep -q "image data"; then
                VALID_IMAGE="true"
            fi
        fi
    fi
    
    # Add comma if not first item
    if [ "$FIRST" = "true" ]; then
        FIRST=false
    else
        echo "," >> "$TEMP_JSON"
    fi
    
    # JSON entry for this file
    echo "    \"$KEY\": {" >> "$TEMP_JSON"
    echo "      \"filename\": \"$FILENAME\"," >> "$TEMP_JSON"
    echo "      \"exists\": $EXISTS," >> "$TEMP_JSON"
    echo "      \"created_during_task\": $CREATED_DURING_TASK," >> "$TEMP_JSON"
    echo "      \"valid_image\": $VALID_IMAGE," >> "$TEMP_JSON"
    echo "      \"decoded_url\": \"$(echo $DECODED_URL | sed 's/"/\\"/g')\"" >> "$TEMP_JSON"
    echo "    }" >> "$TEMP_JSON"
done

echo "  }," >> "$TEMP_JSON"

# Verify Manifest
MANIFEST_EXISTS="false"
MANIFEST_CONTENT=""
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_EXISTS="true"
    # Read content, escape newlines and quotes for JSON
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH" | sed 's/\\/\\\\/g' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
fi

echo "  \"manifest\": {" >> "$TEMP_JSON"
echo "    \"exists\": $MANIFEST_EXISTS," >> "$TEMP_JSON"
echo "    \"content\": \"$MANIFEST_CONTENT\"" >> "$TEMP_JSON"
echo "  }," >> "$TEMP_JSON"

# Screenshot path
echo "  \"screenshot_path\": \"/tmp/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="