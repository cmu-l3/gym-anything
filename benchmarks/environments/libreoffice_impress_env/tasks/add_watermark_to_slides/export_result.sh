#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Watermark Result ==="

TARGET_FILE="/home/ga/Documents/Presentations/benefits_overview.odp"
RESULT_JSON="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close Impress gracefully to ensure file save (if agent forgot, this might trigger save prompt, but we assume agent saved)
# But strictly speaking, we shouldn't interfere too much. 
# We'll just check the file on disk.

# Check file existence and modification
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Perform Internal Verification (Python script running IN container to inspect ODP)
# This is robust because it uses the container's installed odfpy
echo "Running internal verification script..."

python3 << PYEOF
import json
import sys
import os

try:
    from odf.opendocument import load
    from odf import text, draw
except ImportError:
    print("Error: odfpy not available")
    sys.exit(0)

target_file = "$TARGET_FILE"
result = {
    "file_exists": False,
    "file_modified": $FILE_MODIFIED,
    "slide_count": 0,
    "slides_with_draft": [],
    "titles_preserved": 0,
    "error": None
}

if os.path.exists(target_file):
    try:
        result["file_exists"] = True
        doc = load(target_file)
        
        # Count slides
        slides = doc.getElementsByType(draw.Page)
        result["slide_count"] = len(slides)
        
        expected_titles = [
            "2025 Employee Benefits Overview",
            "Health Insurance Plans",
            "Retirement and Savings Programs",
            "Paid Time Off and Leave Policies",
            "Wellness Programs and Perks"
        ]
        
        preserved_count = 0
        draft_flags = []
        
        for i, slide in enumerate(slides):
            # Extract all text from slide
            slide_text = ""
            for elem in slide.getElementsByType(text.P):
                slide_text += str(elem) + " "
            
            # Check for "DRAFT" (case insensitive, but preferably upper)
            # We look for "DRAFT" specifically as requested
            has_draft = "DRAFT" in slide_text
            # Also accept "Draft" or "draft" with penalty in verifier, or strict here?
            # Let's record the exact finding
            if not has_draft and "DRAFT" in slide_text.upper():
                 # Maybe they typed "Draft"
                 pass 
            
            draft_flags.append("DRAFT" in slide_text)
            
            # Check content preservation
            # Simple check: does the expected title exist in the text?
            # Using partial matching because text might be split across spans
            clean_text = slide_text.replace("\n", " ").replace("  ", " ")
            expected = expected_titles[i] if i < len(expected_titles) else ""
            
            # Very loose matching for title preservation
            keywords = expected.split()[:3] # First 3 words
            if all(kw in clean_text for kw in keywords):
                preserved_count += 1
                
        result["slides_with_draft"] = draft_flags
        result["titles_preserved"] = preserved_count
        
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)
print("Internal verification complete.")
PYEOF

# Ensure permissions on result file
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "=== Export Complete ==="
cat "$RESULT_JSON"