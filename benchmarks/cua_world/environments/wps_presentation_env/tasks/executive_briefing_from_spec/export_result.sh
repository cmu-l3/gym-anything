#!/bin/bash
echo "=== Exporting executive_briefing_from_spec results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/executive_briefing_from_spec_end_screenshot.png

BRIEFING_PATH='/home/ga/Documents/executive_briefing.pptx'
ORIGINAL_PATH='/home/ga/Documents/presentations/performance.pptx'
RESULT_FILE='/tmp/executive_briefing_from_spec_result.json'

# Ensure python-pptx is available
pip3 install python-pptx lxml 2>/dev/null || true

python3 << PYEOF
import json
import os
import sys

try:
    from pptx import Presentation
    from pptx.util import Pt
except ImportError:
    result = {
        "error": "python-pptx not available",
        "briefing_exists": False,
    }
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

BRIEFING_PATH = '${BRIEFING_PATH}'
ORIGINAL_PATH = '${ORIGINAL_PATH}'
result = {}

# Check if briefing file exists
if not os.path.exists(BRIEFING_PATH):
    result = {
        "briefing_exists": False,
        "slide_count": 0,
        "slide_titles": [],
        "first_slide_title": "",
        "last_slide_title": "",
        "last_slide_body": "",
        "theme_name": "",
        "original_slide_count": 0,
        "briefing_mtime": 0,
        "original_mtime": 0,
        "error": None,
    }
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f, indent=2)
    print("Briefing file does not exist yet.")
    sys.exit(0)

try:
    prs = Presentation(BRIEFING_PATH)

    slide_titles = []
    last_slide_body = ""
    for i, slide in enumerate(prs.slides):
        title = ""
        body_texts = []
        for shape in slide.shapes:
            if hasattr(shape, "placeholder_format") and shape.placeholder_format is not None:
                idx = shape.placeholder_format.idx
                if idx == 0 and shape.has_text_frame:
                    title = shape.text_frame.text.strip()
                elif shape.has_text_frame:
                    body_texts.append(shape.text_frame.text.strip())
        if not title:
            for shape in slide.shapes:
                if shape.has_text_frame:
                    t = shape.text_frame.text.strip()
                    if t:
                        title = t
                        break
        slide_titles.append(title)
        if i == len(prs.slides) - 1:
            last_slide_body = "\n".join(body_texts)

    # Try to get theme name
    theme_name = ""
    try:
        theme_elem = prs.slide_master.element.find(
            './/{http://schemas.openxmlformats.org/drawingml/2006/main}theme'
        )
        if theme_elem is not None:
            theme_name = theme_elem.get('name', '')
        if not theme_name:
            # Try slide master relationship
            for rel in prs.slide_master.part.rels.values():
                if 'theme' in rel.reltype.lower():
                    try:
                        from lxml import etree
                        tree = etree.fromstring(rel.target_part.blob)
                        name_elem = tree.find('.//{http://schemas.openxmlformats.org/drawingml/2006/main}theme')
                        if name_elem is not None:
                            theme_name = name_elem.get('name', '')
                    except Exception:
                        pass
    except Exception:
        pass

    # Check original file stats
    orig_slide_count = 0
    orig_mtime = 0
    if os.path.exists(ORIGINAL_PATH):
        try:
            orig_prs = Presentation(ORIGINAL_PATH)
            orig_slide_count = len(orig_prs.slides)
        except Exception:
            pass
        orig_mtime = int(os.path.getmtime(ORIGINAL_PATH))

    result = {
        "briefing_exists": True,
        "slide_count": len(prs.slides),
        "slide_titles": slide_titles,
        "first_slide_title": slide_titles[0] if slide_titles else "",
        "last_slide_title": slide_titles[-1] if slide_titles else "",
        "last_slide_body": last_slide_body,
        "theme_name": theme_name,
        "original_slide_count": orig_slide_count,
        "briefing_mtime": int(os.path.getmtime(BRIEFING_PATH)),
        "original_mtime": orig_mtime,
        "error": None,
    }
except Exception as e:
    result = {
        "briefing_exists": True,
        "error": str(e),
        "slide_count": 0,
        "slide_titles": [],
        "first_slide_title": "",
        "last_slide_title": "",
        "last_slide_body": "",
        "theme_name": "",
        "original_slide_count": 0,
        "briefing_mtime": 0,
        "original_mtime": 0,
    }

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported to ${RESULT_FILE}")
print(f"Briefing exists: {result.get('briefing_exists')}")
print(f"Slide count: {result.get('slide_count')}")
print(f"First title: {result.get('first_slide_title', '')[:80]}")
print(f"Last title: {result.get('last_slide_title', '')[:80]}")
PYEOF

echo "=== Export complete ==="
