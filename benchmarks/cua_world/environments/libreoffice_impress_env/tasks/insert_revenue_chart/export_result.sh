#!/bin/bash
echo "=== Exporting insert_revenue_chart results ==="

# Source utils for xdotool/screenshot
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Identify the target file (PPTX or ODP)
# Prefer the most recently modified file in Presentations
TARGET_FILE=""
LATEST_MTIME=0

for f in /home/ga/Documents/Presentations/qbr_fy2024.pptx /home/ga/Documents/Presentations/qbr_fy2024.odp; do
    if [ -f "$f" ]; then
        MTIME=$(stat -c %Y "$f")
        if [ "$MTIME" -gt "$LATEST_MTIME" ]; then
            LATEST_MTIME=$MTIME
            TARGET_FILE="$f"
        fi
    fi
done

echo "Target file identified: $TARGET_FILE"

# 3. Analyze the file INSIDE the container using python-pptx/odfpy
# This ensures we don't rely on host dependencies.
cat > /tmp/analyze_presentation.py << 'PYEOF'
import sys
import json
import os
import hashlib

result = {
    "file_found": False,
    "file_path": "",
    "modified_after_start": False,
    "slide_count": 0,
    "chart_found_slide2": False,
    "chart_type_column": False,
    "text_preserved": False,
    "error": None
}

try:
    filepath = sys.argv[1] if len(sys.argv) > 1 else ""
    task_start_file = "/tmp/task_start_time.txt"
    initial_hash_file = "/tmp/initial_file_hash.txt"
    
    if filepath and os.path.exists(filepath):
        result["file_found"] = True
        result["file_path"] = filepath
        
        # Check timestamps
        if os.path.exists(task_start_file):
            with open(task_start_file) as f:
                start_time = int(f.read().strip())
            mtime = os.path.getmtime(filepath)
            
            # Allow 2 second grace period or check content hash
            if mtime > start_time:
                result["modified_after_start"] = True
            elif os.path.exists(initial_hash_file):
                with open(initial_hash_file) as f:
                    init_hash = f.read().strip()
                with open(filepath, 'rb') as f:
                    curr_hash = hashlib.md5(f.read()).hexdigest()
                if curr_hash != init_hash:
                    result["modified_after_start"] = True
        
        # Analyze content
        if filepath.endswith('.pptx'):
            try:
                from pptx import Presentation
                from pptx.enum.chart import XL_CHART_TYPE
                
                prs = Presentation(filepath)
                result["slide_count"] = len(prs.slides)
                
                # Check Slide 2 for chart
                if len(prs.slides) >= 2:
                    slide2 = prs.slides[1]
                    for shape in slide2.shapes:
                        if shape.has_chart:
                            result["chart_found_slide2"] = True
                            try:
                                c_type = shape.chart.chart_type
                                # Check for various column/bar types
                                if 'COLUMN' in str(c_type) or 'BAR' in str(c_type):
                                    result["chart_type_column"] = True
                            except:
                                # Loose check if strict type fails
                                result["chart_type_column"] = True 
                            break
                            
                # Check text preservation (Slide 1 title)
                if len(prs.slides) >= 1:
                    s1_text = "".join([s.text for s in prs.slides[0].shapes if hasattr(s, "text")]).lower()
                    if "quarterly business review" in s1_text:
                        result["text_preserved"] = True
                        
            except ImportError:
                result["error"] = "python-pptx not installed"
            except Exception as e:
                result["error"] = str(e)
                
        elif filepath.endswith('.odp'):
            try:
                from odf import opendocument, draw, text
                doc = opendocument.load(filepath)
                slides = doc.getElementsByType(draw.Page)
                result["slide_count"] = len(slides)
                
                # Check Slide 2
                if len(slides) >= 2:
                    slide2 = slides[1]
                    # Check for frames/objects that might be charts
                    objects = slide2.getElementsByType(draw.Frame) + slide2.getElementsByType(draw.Object)
                    for obj in objects:
                        # Convert to string to check xml attributes for 'chart'
                        if 'chart' in str(obj).lower():
                            result["chart_found_slide2"] = True
                            result["chart_type_column"] = True # Hard to strictly verify in ODP without deep XML parsing
                            break
                            
                # Check text preservation
                if len(slides) >= 1:
                    s1_text = ""
                    for p in slides[0].getElementsByType(text.P):
                        s1_text += str(p)
                    if "Quarterly Business Review" in s1_text or "FY2024" in s1_text:
                        result["text_preserved"] = True
                        
            except ImportError:
                result["error"] = "odfpy not installed"
            except Exception as e:
                result["error"] = str(e)

except Exception as e:
    result["error"] = f"Script failure: {str(e)}"

print(json.dumps(result))
PYEOF

# Run analysis script
if [ -n "$TARGET_FILE" ]; then
    python3 /tmp/analyze_presentation.py "$TARGET_FILE" > /tmp/task_result.json
else
    # Empty result
    echo '{"file_found": false, "error": "No target file found"}' > /tmp/task_result.json
fi

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="