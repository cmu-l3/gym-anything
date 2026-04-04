#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Save the file (Ctrl+S)
echo "Saving presentation..."
WID=$(get_impress_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    safe_xdotool ga :1 key ctrl+s
    # Give it time to save
    sleep 3
fi

# 2. Capture Final Screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Analyze the ODP file using Python inside the container
# We verify grouping, rotation, and content programmatically here to generate a detailed JSON report
# This avoids needing complex ODP parsing on the host side.

cat << 'PY_ANALYSIS' > /tmp/analyze_odp.py
import json
import sys
import os
import math
from odf.opendocument import load
from odf.draw import Page, G, Frame, Image, Rect, CustomShape
from odf.namespaces import DRAWNS

def get_rotation(element):
    """Extract rotation angle from draw:transform attribute"""
    transform = element.getAttribute('transform')
    if not transform:
        return 0.0
    
    # transform string looks like "rotate(0.157) translate(...) ..."
    # odfpy returns radians usually? Or degrees? 
    # Actually LibreOffice usually saves 'rotate(angle)' where angle is in radians
    
    try:
        parts = transform.split(')')
        for part in parts:
            if 'rotate(' in part:
                val_str = part.split('rotate(')[1].strip()
                return float(val_str)
    except:
        pass
    return 0.0

def analyze_slide(filepath):
    result = {
        "file_exists": False,
        "slide_count": 0,
        "groups_on_slide_2": [],
        "total_images": 0,
        "total_rects": 0
    }
    
    if not os.path.exists(filepath):
        return result
    
    result["file_exists"] = True
    
    try:
        doc = load(filepath)
        slides = doc.getElementsByType(Page)
        result["slide_count"] = len(slides)
        
        if len(slides) < 2:
            return result
            
        target_slide = slides[1] # Slide 2
        
        # Analyze Groups
        groups = target_slide.getElementsByType(G)
        
        for g in groups:
            group_data = {
                "rotation": get_rotation(g),
                "has_image": False,
                "has_rect": False,
                "children_count": 0
            }
            
            # Check children
            images = g.getElementsByType(Image)
            rects = g.getElementsByType(Rect)
            custom_shapes = g.getElementsByType(CustomShape)
            
            if len(images) > 0:
                group_data["has_image"] = True
                result["total_images"] += len(images)
                
            if len(rects) > 0 or len(custom_shapes) > 0:
                group_data["has_rect"] = True
                result["total_rects"] += (len(rects) + len(custom_shapes))
            
            group_data["children_count"] = len(g.childNodes)
            result["groups_on_slide_2"].append(group_data)
            
    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    filepath = "/home/ga/Documents/Presentations/culture_deck.odp"
    analysis = analyze_slide(filepath)
    with open("/tmp/odp_analysis.json", "w") as f:
        json.dump(analysis, f, indent=2)
PY_ANALYSIS

echo "Running ODP analysis..."
python3 /tmp/analyze_odp.py || echo '{"error": "Analysis script failed"}' > /tmp/odp_analysis.json

# 4. Prepare Result JSON
# Combine file stats and analysis
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "/home/ga/Documents/Presentations/culture_deck.odp" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Merge analysis into final result
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "odp_analysis": $(cat /tmp/odp_analysis.json)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="