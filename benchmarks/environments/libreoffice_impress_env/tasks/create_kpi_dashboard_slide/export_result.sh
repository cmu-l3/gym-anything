#!/bin/bash
set -euo pipefail

echo "=== Exporting KPI Dashboard Result ==="

# Define paths
PRESENTATION_PATH="/home/ga/Documents/Presentations/sustainability_report.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SLIDE_COUNT=$(cat /tmp/initial_slide_count.txt 2>/dev/null || echo "4")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$PRESENTATION_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PRESENTATION_PATH")
    FILE_MTIME=$(stat -c %Y "$PRESENTATION_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Run python script inside container to parse the ODP and verify content
# This avoids needing ODF libraries on the host verifier
python3 << PYEOF > /tmp/analysis_output.json
import sys
import json
import re
import os

# Add utils path
sys.path.append('/workspace/utils')

# Mock verification utils if not present (fallback)
try:
    from impress_verification_utils import parse_odp_file, get_slide_count, get_slide_text_content
except ImportError:
    # Minimal fallback implementation if utils are missing
    from odf.opendocument import load
    from odf import text, draw
    
    def parse_odp_file(path):
        try:
            doc = load(path)
            slides = []
            for page in doc.getElementsByType(draw.Page):
                texts = []
                for t in page.getElementsByType(text.P):
                    texts.append(str(t))
                slides.append({"text_elements": texts})
            return {"slides": slides, "slide_count": len(slides)}
        except Exception as e:
            return {"error": str(e)}
            
    def get_slide_count(data):
        return data.get('slide_count', 0)
        
    def get_slide_text_content(data, idx):
        s = data['slides'][idx]
        return "", s.get('text_elements', [])

result = {
    "parse_success": False,
    "slide_count": 0,
    "kpi_slide_found": False,
    "kpi_title_found": False,
    "values_found": {},
    "original_content_preserved": False,
    "error": None
}

path = "$PRESENTATION_PATH"

try:
    if os.path.exists(path):
        data = parse_odp_file(path)
        
        if "error" in data:
            result["error"] = data["error"]
        else:
            result["parse_success"] = True
            result["slide_count"] = get_slide_count(data)
            
            # Check for KPI slide
            all_text_content = []
            kpi_slide_idx = -1
            
            for i in range(result["slide_count"]):
                title, bullets = get_slide_text_content(data, i)
                full_text = (str(title or "") + " " + " ".join(bullets)).lower()
                all_text_content.append(full_text)
                
                # Check for title keywords
                if "kpi" in full_text or "dashboard" in full_text:
                    kpi_slide_idx = i
                    result["kpi_title_found"] = True

            # If no explicit title found, search all slides for values
            # Define patterns
            patterns = {
                "carbon": r"12[,.]?450",
                "energy": r"94\.2",
                "waste": r"78%?",
                "water": r"1\.2"
            }
            
            for key, pat in patterns.items():
                found = False
                for text_content in all_text_content:
                    if re.search(pat, text_content):
                        found = True
                        break
                result["values_found"][key] = found
            
            if any(result["values_found"].values()):
                result["kpi_slide_found"] = True

            # Check preservation
            required_orig = ["quarterly", "environmental goals", "progress summary", "next steps"]
            preserved_count = 0
            combined_text = " ".join(all_text_content)
            for req in required_orig:
                if req in combined_text:
                    preserved_count += 1
            
            result["original_content_preserved"] = (preserved_count >= 3)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Create final JSON result
ANALYSIS=$(cat /tmp/analysis_output.json)

# Construct final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "initial_slide_count": $INITIAL_SLIDE_COUNT,
    "analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="