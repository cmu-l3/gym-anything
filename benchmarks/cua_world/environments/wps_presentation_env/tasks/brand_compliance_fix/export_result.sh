#!/bin/bash
echo "=== Exporting brand_compliance_fix results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/brand_compliance_fix_end_screenshot.png

BRANDED_PATH='/home/ga/Documents/branded_cloudserver.pptx'
ORIGINAL_PATH='/home/ga/Documents/presentations/performance.pptx'
RESULT_FILE='/tmp/brand_compliance_fix_result.json'

pip3 install python-pptx lxml 2>/dev/null || true

python3 << PYEOF
import json
import os
import sys

try:
    from pptx import Presentation
except ImportError:
    result = {"error": "python-pptx not available", "branded_exists": False}
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f)
    sys.exit(0)

BRANDED_PATH = '${BRANDED_PATH}'
ORIGINAL_PATH = '${ORIGINAL_PATH}'

def get_title(slide):
    for shape in slide.shapes:
        if hasattr(shape, 'placeholder_format') and shape.placeholder_format is not None:
            if shape.placeholder_format.idx == 0 and shape.has_text_frame:
                return shape.text_frame.text.strip()
    return ""

def get_body_text(slide):
    texts = []
    for shape in slide.shapes:
        if hasattr(shape, 'placeholder_format') and shape.placeholder_format is not None:
            idx = shape.placeholder_format.idx
            if idx != 0 and shape.has_text_frame:
                texts.append(shape.text_frame.text.strip())
        elif shape.has_text_frame:
            t = shape.text_frame.text.strip()
            if t:
                texts.append(t)
    return "\n".join(texts)

def is_all_caps_title(title):
    # A title is ALL CAPS if every alphabetic char is uppercase and title length > 3
    alpha_chars = [c for c in title if c.isalpha()]
    return len(alpha_chars) > 3 and all(c.isupper() for c in alpha_chars)

if not os.path.exists(BRANDED_PATH):
    result = {
        "branded_exists": False,
        "slide_count": 0,
        "first_slide_title": "",
        "last_slide_title": "",
        "last_slide_body": "",
        "all_caps_titles": [],
        "all_caps_count": 0,
        "slide_titles": [],
        "branded_mtime": 0,
        "error": None,
    }
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f, indent=2)
    print("Branded file does not exist.")
    sys.exit(0)

try:
    prs = Presentation(BRANDED_PATH)

    slide_titles = [get_title(slide) for slide in prs.slides]
    first_title = slide_titles[0] if slide_titles else ""
    last_title = slide_titles[-1] if slide_titles else ""
    last_body = get_body_text(prs.slides[-1]) if prs.slides else ""

    # Find ALL CAPS titles
    all_caps_titles = [
        {"index_1based": i+1, "title": t}
        for i, t in enumerate(slide_titles)
        if is_all_caps_title(t)
    ]

    result = {
        "branded_exists": True,
        "slide_count": len(prs.slides),
        "first_slide_title": first_title,
        "last_slide_title": last_title,
        "last_slide_body": last_body,
        "all_caps_titles": all_caps_titles,
        "all_caps_count": len(all_caps_titles),
        "slide_titles": slide_titles,
        "branded_mtime": int(os.path.getmtime(BRANDED_PATH)),
        "error": None,
    }
except Exception as e:
    result = {
        "branded_exists": True,
        "error": str(e),
        "slide_count": 0,
        "first_slide_title": "",
        "last_slide_title": "",
        "last_slide_body": "",
        "all_caps_titles": [],
        "all_caps_count": 0,
        "slide_titles": [],
        "branded_mtime": 0,
    }

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported to ${RESULT_FILE}")
print(f"Branded file exists: {result.get('branded_exists')}")
print(f"First slide title: '{result.get('first_slide_title', '')[:80]}'")
print(f"Last slide title: '{result.get('last_slide_title', '')}'")
print(f"ALL CAPS titles remaining: {result.get('all_caps_count')}")
print(f"Last slide body excerpt: '{result.get('last_slide_body', '')[:100]}'")
PYEOF

echo "=== Export complete ==="
