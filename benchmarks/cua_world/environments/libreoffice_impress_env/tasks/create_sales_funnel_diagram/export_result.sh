#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sales Funnel Result ==="

# 1. Save the file (Ctrl+S)
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Sending Save command..."
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 3
fi

# 2. Record End State
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/Presentations/pipeline_review.odp"

# Check file modification
FILE_MODIFIED="false"
if [ -f "$FILE_PATH" ]; then
    CURRENT_MTIME=$(stat -c %Y "$FILE_PATH")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Analyze the ODP file structure using Python (odfpy)
# We run this INSIDE the container to leverage installed libraries and direct file access
echo "Analyzing ODP structure..."
cat << 'PYEOF' > /tmp/analyze_funnel.py
import sys
import json
import re
from odf.opendocument import load
from odf.draw import Page, Frame, CustomShape, G
from odf.text import P

def get_frame_geometry(frame):
    """Extract geometry from an ODF draw frame."""
    try:
        # ODF uses distinct attributes for geometry, usually in cm or inches string
        x = frame.getAttribute('x') or '0cm'
        y = frame.getAttribute('y') or '0cm'
        w = frame.getAttribute('width') or '0cm'
        h = frame.getAttribute('height') or '0cm'
        
        def parse_measure(m):
            if not m: return 0.0
            val = float(re.findall(r"[-+]?\d*\.\d+|\d+", m)[0])
            if 'in' in m: return val * 2.54
            if 'mm' in m: return val / 10.0
            if 'pt' in m: return val * 0.0352778
            return val # assume cm
            
        return {
            'x': parse_measure(x),
            'y': parse_measure(y),
            'w': parse_measure(w),
            'h': parse_measure(h)
        }
    except Exception as e:
        return {'x':0, 'y':0, 'w':0, 'h':0, 'error': str(e)}

def get_text_content(element):
    """Recursively extract text from an element."""
    text_content = []
    for child in element.childNodes:
        if child.qname[1] == 'P': # text:p
            for text_node in child.childNodes:
                if text_node.nodeType == 3: # Text node
                    text_content.append(str(text_node))
        else:
            text_content.extend(get_text_content(child))
    return " ".join(text_content).strip()

def analyze_presentation(filepath):
    try:
        doc = load(filepath)
        slides = doc.getElementsByType(Page)
        
        result = {
            "slide_count": len(slides),
            "funnel_slide_found": False,
            "shapes": [],
            "funnel_analysis": {
                "is_sorted_y": False,
                "is_tapered_width": False,
                "text_matches": [],
                "distinct_colors": False
            }
        }
        
        if len(slides) < 2:
            return result
            
        # Analyze Slide 2
        slide2 = slides[1]
        result["funnel_slide_found"] = True
        
        # Get all shapes (frames and custom shapes)
        # Flatten groups if necessary
        shapes = []
        
        def collect_shapes(element):
            for child in element.childNodes:
                if child.qname[1] in ['frame', 'custom-shape', 'rect', 'ellipse', 'path', 'polygon']:
                    shapes.append(child)
                elif child.qname[1] == 'g': # Group
                    collect_shapes(child)
        
        collect_shapes(slide2)
        
        # Process shapes
        shape_data = []
        for s in shapes:
            geo = get_frame_geometry(s)
            txt = get_text_content(s)
            
            # Try to get fill color (simplified, often in style)
            # This is complex in ODF (indirect reference), so we might skip rigorous color check here
            # and rely on shape count/geometry/text
            
            if geo['w'] > 0 and geo['h'] > 0: # Filter out zero-size artifacts
                shape_data.append({
                    'geometry': geo,
                    'text': txt,
                    'type': s.qname[1]
                })
        
        # Filter relevant funnel shapes (those containing specific text)
        expected_keywords = ["Inquiries", "MQL", "SQL", "Closed"]
        funnel_shapes = []
        
        for shape in shape_data:
            for kw in expected_keywords:
                if kw in shape['text']:
                    funnel_shapes.append(shape)
                    break
        
        result["shapes"] = funnel_shapes
        
        # Analyze funnel geometry if we found shapes
        if len(funnel_shapes) >= 2:
            # Sort by Y position (Top to Bottom)
            sorted_shapes = sorted(funnel_shapes, key=lambda s: s['geometry']['y'])
            
            # Check 1: Text order matches Y order?
            # Expected order: Inquiries (top), MQL, SQL, Closed (bottom)
            text_order_correct = True
            current_idx = -1
            for shape in sorted_shapes:
                txt = shape['text']
                found_idx = -1
                if "Inquiries" in txt: found_idx = 0
                elif "MQL" in txt: found_idx = 1
                elif "SQL" in txt: found_idx = 2
                elif "Closed" in txt: found_idx = 3
                
                if found_idx != -1:
                    if found_idx < current_idx:
                        text_order_correct = False
                    current_idx = found_idx
            
            result["funnel_analysis"]["is_sorted_y"] = text_order_correct
            
            # Check 2: Width tapering (Top width > Bottom width)
            # We check if width generally decreases
            widths = [s['geometry']['w'] for s in sorted_shapes]
            # Allow some noise, but trend should be decreasing
            is_tapered = True
            for i in range(len(widths) - 1):
                if widths[i] < widths[i+1]: # Top should be wider than bottom
                     # Strict check might fail if they make a cylinder, but prompt asked for funnel
                     is_tapered = False
            
            result["funnel_analysis"]["is_tapered_width"] = is_tapered
            
            # Check 3: Text matches
            matches = []
            for kw in expected_keywords:
                found = any(kw in s['text'] for s in funnel_shapes)
                matches.append(found)
            result["funnel_analysis"]["text_matches"] = matches

        return result
        
    except Exception as e:
        return {"error": str(e)}

analysis = analyze_presentation("/home/ga/Documents/Presentations/pipeline_review.odp")
with open("/tmp/odp_analysis.json", "w") as f:
    json.dump(analysis, f, indent=2)
PYEOF

python3 /tmp/analyze_funnel.py

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
ANALYSIS_CONTENT=$(cat /tmp/odp_analysis.json 2>/dev/null || echo "{}")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "analysis": $ANALYSIS_CONTENT,
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="