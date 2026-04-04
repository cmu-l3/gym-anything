#!/bin/bash
# Export script for CSS and JavaScript Frontend Resource Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting CSS/JS Resource Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
REPORT_PATH="$REPORTS_DIR/frontend_resources_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
SF_RUNNING="false"
WINDOW_INFO=""
CSS_CSV_FOUND="false"
CSS_CSV_PATH=""
JS_CSV_FOUND="false"
JS_CSV_PATH=""
FILES_ARE_DISTINCT="false"
REPORT_FOUND="false"
REPORT_SIZE=0
REPORT_CONTENT_VALID="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# --- Analyze Exported CSVs ---
# We need to find two distinct files: one with CSS data, one with JS data.
# We look at content, not just filenames, to be robust.

if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Only check files created/modified after task start
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            # Read sample lines
            CONTENT=$(head -20 "$csv_file" 2>/dev/null || echo "")
            
            # Check for CSS indicators (.css extension in URLs, text/css mime type)
            IS_CSS="false"
            if echo "$CONTENT" | grep -qi "\.css"; then
                IS_CSS="true"
            fi
            
            # Check for JS indicators (.js extension in URLs, javascript mime type)
            IS_JS="false"
            if echo "$CONTENT" | grep -qi "\.js"; then
                IS_JS="true"
            fi
            
            # Identify the file type (prioritize specific content checks)
            # Note: A "Internal - All" export might contain both, but we want separate tab exports usually.
            # However, if the user filtered specifically, we accept that too.
            
            if [ "$IS_CSS" = "true" ] && [ "$IS_JS" = "false" ]; then
                CSS_CSV_FOUND="true"
                CSS_CSV_PATH="$csv_file"
            elif [ "$IS_JS" = "true" ] && [ "$IS_CSS" = "false" ]; then
                JS_CSV_FOUND="true"
                JS_CSV_PATH="$csv_file"
            elif [ "$IS_CSS" = "true" ] && [ "$IS_JS" = "true" ]; then
                # File contains both - might be a bulk export.
                # We'll mark it, but ideally we want separate files.
                # We assign to both temporarily, but the "Files Are Distinct" check will fail if it's the same file.
                if [ "$CSS_CSV_FOUND" = "false" ]; then CSS_CSV_PATH="$csv_file"; fi
                if [ "$JS_CSV_FOUND" = "false" ]; then JS_CSV_PATH="$csv_file"; fi
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# Check if we found distinct files
if [ -n "$CSS_CSV_PATH" ] && [ -n "$JS_CSV_PATH" ]; then
    if [ "$CSS_CSV_PATH" != "$JS_CSV_PATH" ]; then
        FILES_ARE_DISTINCT="true"
        # Re-confirm found status
        CSS_CSV_FOUND="true"
        JS_CSV_FOUND="true"
    else
        FILES_ARE_DISTINCT="false"
        # If both point to same file, determining which it "really" is is ambiguous, 
        # but we likely have a mixed export.
    fi
fi

# --- Analyze Report ---
if [ -f "$REPORT_PATH" ]; then
    REPORT_FOUND="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check for meaningful content
    REPORT_TEXT=$(cat "$REPORT_PATH" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    
    HAS_CSS_KEYWORD=$(echo "$REPORT_TEXT" | grep -q "css" && echo "true" || echo "false")
    HAS_JS_KEYWORD=$(echo "$REPORT_TEXT" | grep -qE "js|javascript" && echo "true" || echo "false")
    HAS_NUMBERS=$(echo "$REPORT_TEXT" | grep -qE "[0-9]+" && echo "true" || echo "false")
    
    if [ "$HAS_CSS_KEYWORD" = "true" ] && [ "$HAS_JS_KEYWORD" = "true" ] && [ "$HAS_NUMBERS" = "true" ]; then
        REPORT_CONTENT_VALID="true"
    fi
fi

# Write result JSON using Python
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "css_csv_found": "$CSS_CSV_FOUND" == "true",
    "css_csv_path": "$CSS_CSV_PATH",
    "js_csv_found": "$JS_CSV_FOUND" == "true",
    "js_csv_path": "$JS_CSV_PATH",
    "files_are_distinct": "$FILES_ARE_DISTINCT" == "true",
    "report_found": "$REPORT_FOUND" == "true",
    "report_size": $REPORT_SIZE,
    "report_content_valid": "$REPORT_CONTENT_VALID" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/css_js_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/css_js_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="