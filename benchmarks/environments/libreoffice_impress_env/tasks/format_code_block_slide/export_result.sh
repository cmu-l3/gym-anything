#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Format Code Block Slide Result ==="

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PRESENTATION_PATH="/home/ga/Documents/Presentations/api_docs_v2.odp"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract properties from the ODP file using Python
# We do this inside the container because odfpy is installed here
echo "Analyzing ODP file..."
python3 -c "
import sys
import json
import os
import zipfile
from odf import opendocument, text, draw, style
from odf.namespaces import DRAWNS, TEXTNS, STYLENS, FOXNS

result = {
    'file_exists': False,
    'slide_count': 0,
    'last_slide_title': '',
    'json_content_found': False,
    'monospace_font_found': False,
    'background_color_found': False,
    'border_found': False,
    'details': {}
}

filepath = '$PRESENTATION_PATH'

if os.path.exists(filepath):
    result['file_exists'] = True
    try:
        doc = opendocument.load(filepath)
        slides = doc.getElementsByType(draw.Page)
        result['slide_count'] = len(slides)
        
        if len(slides) >= 3:
            last_slide = slides[-1] # Usually the new one
            
            # Check Text Content
            all_text = []
            for t in last_slide.getElementsByType(text.P):
                all_text.append(str(t))
            full_text = ' '.join(all_text)
            
            # Check for title (heuristic: first text box or specific strings)
            result['last_slide_title'] = full_text[:50] # approx
            
            # Check for JSON content
            if 'usr_8742_x9' in full_text and 'sysadmin' in full_text:
                result['json_content_found'] = True
            
            # --- Check Formatting ---
            # We need to find the text box containing the code
            # and check its style for font, area fill, and border.
            
            # Helper to find style by name
            def get_style(style_name, family):
                for s in doc.styles.getElementsByType(style.Style):
                    if s.getAttribute('name') == style_name and s.getAttribute('family') == family:
                        return s
                for s in doc.automaticstyles.getElementsByType(style.Style):
                    if s.getAttribute('name') == style_name and s.getAttribute('family') == family:
                        return s
                return None

            monospaced_fonts = ['liberation mono', 'courier', 'consolas', 'monospace', 'dejavu sans mono']
            
            # Check frames/textboxes
            for frame in last_slide.getElementsByType(draw.Frame):
                # 1. Check Font in text contents
                # Text usually has a paragraph style or span style
                for p in frame.getElementsByType(text.P):
                    p_style_name = p.getAttribute('stylename')
                    if p_style_name:
                        s = get_style(p_style_name, 'paragraph')
                        if s:
                             # Check TextProperties
                             for tp in s.getElementsByType(style.TextProperties):
                                font = tp.getAttribute('fontname')
                                if font and any(m in font.lower() for m in monospaced_fonts):
                                    result['monospace_font_found'] = True
                
                # Also check span styles (T)
                for span in frame.getElementsByType(text.Span):
                    span_style = span.getAttribute('stylename')
                    if span_style:
                        s = get_style(span_style, 'text')
                        if s:
                             for tp in s.getElementsByType(style.TextProperties):
                                font = tp.getAttribute('fontname')
                                if font and any(m in font.lower() for m in monospaced_fonts):
                                    result['monospace_font_found'] = True

                # 2. Check Background and Border (Graphic Properties of the Frame)
                style_name = frame.getAttribute('stylename')
                if style_name:
                    s = get_style(style_name, 'graphic')
                    if s:
                        for gp in s.getElementsByType(style.GraphicProperties):
                            # Check Fill
                            fill = gp.getAttribute('fill')
                            fill_color = gp.getAttribute('fillcolor')
                            
                            if fill in ['solid', 'color']:
                                # Check for gray-ish color
                                # Format usually #RRGGBB
                                if fill_color:
                                    try:
                                        r = int(fill_color[1:3], 16)
                                        g = int(fill_color[3:5], 16)
                                        b = int(fill_color[5:7], 16)
                                        # Gray has low saturation (r~g~b) and is light (>180)
                                        if abs(r-g) < 20 and abs(g-b) < 20 and r > 180:
                                            result['background_color_found'] = True
                                    except:
                                        pass
                            
                            # Check Border (stroke)
                            stroke = gp.getAttribute('stroke') # 'solid', 'dash', etc.
                            stroke_color = gp.getAttribute('strokecolor')
                            # 'none' is default for stroke
                            if stroke and stroke != 'none':
                                result['border_found'] = True

    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
" > /tmp/analysis_result.json

# 3. Check File Timestamps
if [ -f "$PRESENTATION_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$PRESENTATION_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    FILE_MODIFIED="false"
fi

# 4. Create Final Result JSON
# Merge python analysis with file stats
jq -n \
    --argfile analysis /tmp/analysis_result.json \
    --arg modified "$FILE_MODIFIED" \
    --arg screenshot "/tmp/task_final.png" \
    '{
        analysis: $analysis,
        file_modified_during_task: ($modified == "true"),
        screenshot_path: $screenshot
    }' > /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json