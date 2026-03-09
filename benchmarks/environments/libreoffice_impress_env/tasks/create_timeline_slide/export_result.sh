#!/bin/bash
set -e
echo "=== Exporting Create Cloud Migration Timeline Slide Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PRESENTATION_PATH="/home/ga/Documents/Presentations/it_strategy.odp"

# Try to save the file one last time in case agent forgot (optional, but helpful for evaluation)
# Only do this if window is active
if DISPLAY=:1 wmctrl -l | grep -q "LibreOffice Impress"; then
    echo "Attempting safety save..."
    wid=$(get_impress_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        safe_xdotool ga :1 key --delay 200 ctrl+s
        sleep 2
    fi
fi

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file stats
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE_BYTES=0

if [ -f "$PRESENTATION_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$PRESENTATION_PATH")
    FILE_MTIME=$(stat -c %Y "$PRESENTATION_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Run internal verification script to parse ODP
# We do this INSIDE container to guarantee odfpy availability
cat > /tmp/internal_verify.py << 'PYEOF'
import json
import sys
import os

# Add utils to path inside container
sys.path.insert(0, '/workspace/utils')

try:
    from impress_verification_utils import parse_odp_file, get_slide_count, get_slide_text_content
    
    filepath = "/home/ga/Documents/Presentations/it_strategy.odp"
    result = {
        "parsed_successfully": False,
        "slide_count": 0,
        "slide4_text": "",
        "slide4_shape_count": 0,
        "milestones_found": [],
        "quarters_found": [],
        "error": None
    }
    
    if os.path.exists(filepath):
        data = parse_odp_file(filepath)
        
        if 'error' not in data:
            result["parsed_successfully"] = True
            result["slide_count"] = get_slide_count(data)
            
            # Get content of Slide 4 (index 3)
            if result["slide_count"] >= 4:
                # Text
                slides = data.get('slides', [])
                slide4 = slides[3]
                text_elements = slide4.get('text_elements', [])
                all_text = ' '.join(text_elements).lower()
                result["slide4_text"] = all_text
                
                # Shapes
                result["slide4_shape_count"] = slide4.get('shape_count', 0)
                
                # Check milestones
                milestones = [
                    "assessment", "planning", "infrastructure", "setup", 
                    "data migration", "application", "optimization", "handoff"
                ]
                result["milestones_found"] = [m for m in milestones if m in all_text]
                
                # Check quarters
                quarters = ["q1 2025", "q2 2025", "q3 2025", "q4 2025", "q1 2026"]
                result["quarters_found"] = [q for q in quarters if q in all_text]
                
        else:
            result["error"] = data['error']
            
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"parsed_successfully": False, "error": str(e)}))
PYEOF

# Execute verification and capture JSON output
ODP_ANALYSIS=$(python3 /tmp/internal_verify.py)

# Construct final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "screenshot_path": "/tmp/task_final.png",
    "odp_analysis": $ODP_ANALYSIS
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="