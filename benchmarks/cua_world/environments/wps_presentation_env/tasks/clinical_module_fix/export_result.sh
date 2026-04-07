#!/bin/bash
echo "=== Exporting clinical_module_fix results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/clinical_module_fix_end_screenshot.png

OUTPUT_PPTX='/home/ga/Documents/ACLS_corrected.pptx'
ORIGINAL_PPTX='/home/ga/Documents/ACLS_lecture.pptx'
RESULT_FILE='/tmp/clinical_module_fix_result.json'

pip3 install python-pptx lxml 2>/dev/null || true

python3 << PYEOF
import json
import os

try:
    from pptx import Presentation
except ImportError:
    with open('${RESULT_FILE}', 'w') as f:
        json.dump({"error": "python-pptx not available"}, f)
    raise SystemExit(0)

OUTPUT_PPTX = '${OUTPUT_PPTX}'
ORIGINAL_PPTX = '${ORIGINAL_PPTX}'

result = {
    "output_exists": False,
    "output_slide_count": 0,
    "output_titles": [],
    "pals_slides_remaining": [],     # slides still containing PALS/Pediatric content
    "original_slide_count": 0,
    "original_unchanged": False,
    "output_mtime": 0,
    "error": None,
}

if not os.path.exists(OUTPUT_PPTX):
    result["error"] = "Output file not found at " + OUTPUT_PPTX
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f, indent=2)
    raise SystemExit(0)

result["output_exists"] = True
result["output_mtime"] = int(os.path.getmtime(OUTPUT_PPTX))

PALS_KEYWORDS = ["pals", "pediatric", "weight-based", "broselow", "0.01 mg/kg", "2 j/kg", "5 mg/kg"]

try:
    prs = Presentation(OUTPUT_PPTX)
    slide_titles = []
    pals_remaining = []
    for i, slide in enumerate(prs.slides):
        title_text = ""
        body_text = ""
        for shape in slide.shapes:
            if not shape.has_text_frame:
                continue
            if hasattr(shape, "placeholder_format") and shape.placeholder_format is not None:
                if shape.placeholder_format.idx == 0:
                    title_text = shape.text_frame.text.strip()
                elif shape.placeholder_format.idx == 1:
                    body_text = shape.text_frame.text.strip()
        slide_info = {"pos": i + 1, "title": title_text, "body_preview": body_text[:200]}
        slide_titles.append(slide_info)
        # Check for PALS keywords in title or body
        combined = (title_text + " " + body_text).lower()
        found_kw = [kw for kw in PALS_KEYWORDS if kw in combined]
        if found_kw:
            pals_remaining.append({
                "pos": i + 1,
                "title": title_text,
                "matched_keywords": found_kw
            })
    result["output_slide_count"] = len(prs.slides)
    result["output_titles"] = slide_titles
    result["pals_slides_remaining"] = pals_remaining
except Exception as e:
    result["error"] = "Error reading output: " + str(e)

# Check original unchanged
try:
    orig = Presentation(ORIGINAL_PPTX)
    result["original_slide_count"] = len(orig.slides)
    result["original_unchanged"] = (len(orig.slides) == 22)
except Exception as e:
    result["original_unchanged"] = False
    result["original_slide_count"] = -1

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Output: {result['output_slide_count']} slides")
print(f"PALS slides remaining: {len(result['pals_slides_remaining'])}")
print(f"Original unchanged: {result['original_unchanged']} ({result['original_slide_count']} slides)")
PYEOF

echo "=== Export complete: ${RESULT_FILE} ==="
