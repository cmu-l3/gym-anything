#!/bin/bash
# Export script for Generate Patient CCD Task

echo "=== Exporting Generate Patient CCD Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
sleep 1
take_screenshot /tmp/task_final_screenshot.png
echo "Final screenshot saved"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Target patient details
PATIENT_PID=5
PATIENT_FNAME="Rickie"
PATIENT_LNAME="Batz"
PATIENT_DOB="1990-08-14"

# Search for XML files created after task start
echo ""
echo "=== Searching for CCD/XML files created during task ==="

# Define search locations
SEARCH_LOCATIONS=(
    "/home/ga/Downloads"
    "/home/ga"
    "/tmp"
)

# Find all XML files modified after task start
CCD_FILE_FOUND="false"
CCD_FILE_PATH=""
CCD_FILE_SIZE=0
CCD_CONTENT_PREVIEW=""
VALID_CCD_FORMAT="false"
CONTAINS_PATIENT_DATA="false"
CONTAINS_CLINICAL_CONTENT="false"

echo "Looking for XML files created after timestamp $TASK_START..."

for location in "${SEARCH_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        # Find XML files modified after task start
        while IFS= read -r filepath; do
            if [ -n "$filepath" ] && [ -f "$filepath" ]; then
                FILE_MTIME=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
                
                if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
                    echo "Found new file: $filepath (mtime: $FILE_MTIME)"
                    
                    # Read file content for analysis
                    CONTENT=$(cat "$filepath" 2>/dev/null | head -c 50000)
                    
                    # Check if it's a CCD/CCDA document
                    if echo "$CONTENT" | grep -q "ClinicalDocument"; then
                        echo "  -> Contains ClinicalDocument marker - this is a CCD!"
                        CCD_FILE_FOUND="true"
                        CCD_FILE_PATH="$filepath"
                        CCD_FILE_SIZE=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
                        VALID_CCD_FORMAT="true"
                        
                        # Get content preview (first 2000 chars for analysis)
                        CCD_CONTENT_PREVIEW=$(echo "$CONTENT" | head -c 2000)
                        
                        # Check for patient identifiers
                        if echo "$CONTENT" | grep -qi "$PATIENT_FNAME" && echo "$CONTENT" | grep -qi "$PATIENT_LNAME"; then
                            echo "  -> Contains patient name: $PATIENT_FNAME $PATIENT_LNAME"
                            CONTAINS_PATIENT_DATA="true"
                        elif echo "$CONTENT" | grep -q "$PATIENT_DOB"; then
                            echo "  -> Contains patient DOB: $PATIENT_DOB"
                            CONTAINS_PATIENT_DATA="true"
                        fi
                        
                        # Check for clinical sections
                        if echo "$CONTENT" | grep -qiE "(problem|medication|allergy|component)"; then
                            echo "  -> Contains clinical content sections"
                            CONTAINS_CLINICAL_CONTENT="true"
                        fi
                        
                        # Found a valid CCD, stop searching
                        break 2
                    else
                        echo "  -> Not a CCD document (no ClinicalDocument marker)"
                    fi
                fi
            fi
        done < <(find "$location" -maxdepth 3 -name "*.xml" -type f 2>/dev/null)
    fi
done

# Also check for HTML files that might contain CCD (some browsers save as HTML)
if [ "$CCD_FILE_FOUND" = "false" ]; then
    echo ""
    echo "No XML found, checking for HTML files with CCD content..."
    for location in "${SEARCH_LOCATIONS[@]}"; do
        if [ -d "$location" ]; then
            while IFS= read -r filepath; do
                if [ -n "$filepath" ] && [ -f "$filepath" ]; then
                    FILE_MTIME=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
                    
                    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
                        CONTENT=$(cat "$filepath" 2>/dev/null | head -c 50000)
                        
                        if echo "$CONTENT" | grep -qi "ClinicalDocument\|CCD\|Continuity of Care"; then
                            echo "Found CCD-related HTML: $filepath"
                            CCD_FILE_FOUND="true"
                            CCD_FILE_PATH="$filepath"
                            CCD_FILE_SIZE=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
                            
                            if echo "$CONTENT" | grep -qi "$PATIENT_FNAME"; then
                                CONTAINS_PATIENT_DATA="true"
                            fi
                            break 2
                        fi
                    fi
                fi
            done < <(find "$location" -maxdepth 3 \( -name "*.html" -o -name "*.htm" \) -type f 2>/dev/null)
        fi
    done
fi

# Check if Firefox shows CCD content (via window title or page source)
echo ""
echo "Checking Firefox state..."
FIREFOX_RUNNING="false"
FIREFOX_TITLE=""
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
    FIREFOX_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
    echo "Firefox window title: $FIREFOX_TITLE"
    
    # Check if window title suggests CCD was generated
    if echo "$FIREFOX_TITLE" | grep -qiE "(ccd|clinical|document|xml)"; then
        echo "Firefox title suggests CCD may be displayed"
    fi
fi

# List all new files for debugging
echo ""
echo "=== All files created during task ==="
find /home/ga/Downloads /home/ga /tmp -maxdepth 2 -type f -newer /tmp/task_start_timestamp 2>/dev/null | head -20

# Save CCD content to temp file if found
if [ "$CCD_FILE_FOUND" = "true" ] && [ -f "$CCD_FILE_PATH" ]; then
    cp "$CCD_FILE_PATH" /tmp/generated_ccd.xml 2>/dev/null || true
    chmod 644 /tmp/generated_ccd.xml 2>/dev/null || true
    echo ""
    echo "CCD file copied to /tmp/generated_ccd.xml for verification"
fi

# Escape special characters for JSON
CCD_FILE_PATH_ESCAPED=$(echo "$CCD_FILE_PATH" | sed 's/"/\\"/g')
FIREFOX_TITLE_ESCAPED=$(echo "$FIREFOX_TITLE" | sed 's/"/\\"/g')

# Create result JSON
echo ""
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/ccd_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "patient": {
        "pid": $PATIENT_PID,
        "fname": "$PATIENT_FNAME",
        "lname": "$PATIENT_LNAME",
        "dob": "$PATIENT_DOB"
    },
    "ccd_file_found": $CCD_FILE_FOUND,
    "ccd_file_path": "$CCD_FILE_PATH_ESCAPED",
    "ccd_file_size_bytes": $CCD_FILE_SIZE,
    "valid_ccd_format": $VALID_CCD_FORMAT,
    "contains_patient_data": $CONTAINS_PATIENT_DATA,
    "contains_clinical_content": $CONTAINS_CLINICAL_CONTENT,
    "firefox_running": $FIREFOX_RUNNING,
    "firefox_title": "$FIREFOX_TITLE_ESCAPED",
    "screenshot_exists": $([ -f "/tmp/task_final_screenshot.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result JSON
rm -f /tmp/generate_ccd_result.json 2>/dev/null || sudo rm -f /tmp/generate_ccd_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/generate_ccd_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/generate_ccd_result.json
chmod 666 /tmp/generate_ccd_result.json 2>/dev/null || sudo chmod 666 /tmp/generate_ccd_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/generate_ccd_result.json
echo ""
echo "=== Export Complete ==="