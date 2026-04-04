#!/bin/bash
echo "=== Exporting Fix Slide Layout Result ==="

# Record task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/Presentations/product_launch_fixed.odp"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python analysis SCRIPT INSIDE CONTAINER to parse ODP
# We do this here because the container has odfpy installed, while the host/verifier might not.
cat > /tmp/analyze_odp.py << 'PYEOF'
import sys
import json
import os
import zipfile
from xml.dom import minidom

# We use basic XML parsing if odfpy isn't behaving, or odfpy if available.
# Since we installed odfpy in setup, we'll try to use it, but fallback to direct XML for robustness.
try:
    from odf import opendocument
    from odf.draw import Page, Frame
    from odf.text import P
    from odf.style import Style, ParagraphProperties, GraphicProperties, TextProperties
    ODFPY_AVAILABLE = True
except ImportError:
    ODFPY_AVAILABLE = False

def analyze_presentation(filepath):
    results = {
        "file_exists": False,
        "is_valid_odp": False,
        "slide_count": 0,
        "title_centered": False,
        "columns_applied": False,
        "overlap_fixed": False,
        "font_size_fixed": False,
        "content_preserved": False
    }

    if not os.path.exists(filepath):
        return results
    
    results["file_exists"] = True
    
    try:
        if ODFPY_AVAILABLE:
            doc = opendocument.load(filepath)
            
            # --- Check Slide Count ---
            # Note: odfpy structure for slides is doc.presentation.getElementsByType(Page)
            slides = doc.presentation.getElementsByType(Page)
            results["slide_count"] = len(slides)
            
            if len(slides) >= 4:
                # --- Slide 1: Alignment ---
                # Check for "Nebula Platform Launch"
                # Need to find the specific Paragraph and check its style
                s1_title_node = None
                for p in slides[0].getElementsByType(P):
                    if "Nebula Platform Launch" in str(p):
                        s1_title_node = p
                        break
                
                if s1_title_node:
                    style_name = s1_title_node.getAttribute("stylename")
                    # Find style definition
                    style = doc.getStyleByName(style_name)
                    if style:
                        pp = style.getElementsByType(ParagraphProperties)
                        if pp and pp[0].getAttribute("textalign") == "center":
                            results["title_centered"] = True
                
                # --- Slide 2: Columns ---
                # Look for text box with "Real-time Analytics"
                s2_frame = None
                for frame in slides[1].getElementsByType(Frame):
                    # Check text content
                    txt = ""
                    for p in frame.getElementsByType(P):
                        txt += str(p)
                    if "Real-time Analytics" in txt:
                        s2_frame = frame
                        break
                
                if s2_frame:
                    # Columns are usually defined in the GraphicProperties of the style
                    # OR explicitly in the style:columns element
                    style_name = s2_frame.getAttribute("stylename")
                    style = doc.getStyleByName(style_name)
                    if style:
                        # Inspect style children for <style:columns>
                        for child in style.childNodes:
                            if child.tagName == "style:columns":
                                if child.getAttribute("columncount") == "2":
                                    results["columns_applied"] = True

                # --- Slide 3: Overlap/Position ---
                # Look for "Enterprise Plan"
                s3_frame = None
                for frame in slides[2].getElementsByType(Frame):
                    txt = ""
                    for p in frame.getElementsByType(P):
                        txt += str(p)
                    if "Enterprise Plan" in txt:
                        s3_frame = frame
                        break
                
                if s3_frame:
                    # Check Y position
                    y_str = s3_frame.getAttribute("y")
                    # Parse "0.5cm" -> 0.5
                    try:
                        unit = "".join([c for c in y_str if c.isalpha()])
                        val = float("".join([c for c in y_str if c.isdigit() or c == '.']))
                        # Basic conversion to cm
                        y_cm = val
                        if unit == "in": y_cm = val * 2.54
                        if unit == "mm": y_cm = val / 10.0
                        
                        # If it was 0.5cm (initial), it fails. If > 2.5cm, it's likely fixed
                        if y_cm > 2.5:
                            results["overlap_fixed"] = True
                    except:
                        pass

                # --- Slide 4: Font Size ---
                # Look for email
                s4_p_node = None
                for p in slides[3].getElementsByType(P):
                    if "support@nebula.io" in str(p):
                        s4_p_node = p
                        break
                
                if s4_p_node:
                    style_name = s4_p_node.getAttribute("stylename")
                    style = doc.getStyleByName(style_name)
                    if style:
                        tp = style.getElementsByType(TextProperties)
                        if tp:
                            fs = tp[0].getAttribute("fontsize")
                            if fs == "24pt":
                                results["font_size_fixed"] = True

                results["is_valid_odp"] = True
                
                # Content Check
                list_items = 0
                for p in slides[1].getElementsByType(P):
                    if "•" in str(p):
                        list_items += 1
                if list_items >= 18:
                    results["content_preserved"] = True

    except Exception as e:
        results["error"] = str(e)

    return results

if __name__ == "__main__":
    filepath = "/home/ga/Documents/Presentations/product_launch_fixed.odp"
    data = analyze_presentation(filepath)
    print(json.dumps(data))
PYEOF

# Execute the analysis script
echo "Running ODP analysis..."
ANALYSIS_JSON=$(python3 /tmp/analyze_odp.py)
echo "Analysis result: $ANALYSIS_JSON"

# Check file stats
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"