#!/bin/bash
echo "=== Exporting investor_pitch_audit results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/investor_pitch_audit_end_screenshot.png

OUTPUT_PPTX='/home/ga/Documents/Q3_board_corrected.pptx'
ORIGINAL_PPTX='/home/ga/Documents/financial_report.pptx'
RESULT_FILE='/tmp/investor_pitch_audit_result.json'

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
    "q2_slides_remaining": [],          # slide 1-indexed positions still saying Q2
    "competitor_slide_titles": [],       # slides mentioning Apex Digital
    "fls_slide_position": None,         # 1-indexed position of FLS disclaimer
    "fls_slide_title": "",
    "fls_body_text": "",
    "original_slide_count": 0,
    "original_unchanged": False,
    "original_first_title": "",
    "output_mtime": 0,
    "error": None,
}

# Check output file
if not os.path.exists(OUTPUT_PPTX):
    result["error"] = "Output file not found at " + OUTPUT_PPTX
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f, indent=2)
    raise SystemExit(0)

result["output_exists"] = True
result["output_mtime"] = int(os.path.getmtime(OUTPUT_PPTX))

try:
    prs = Presentation(OUTPUT_PPTX)
    slide_titles = []
    for i, slide in enumerate(prs.slides):
        title_text = ""
        body_text = ""
        for shape in slide.shapes:
            if shape.has_text_frame:
                if hasattr(shape, "placeholder_format") and shape.placeholder_format is not None:
                    if shape.placeholder_format.idx == 0:
                        title_text = shape.text_frame.text.strip()
                    elif shape.placeholder_format.idx == 1:
                        body_text = shape.text_frame.text.strip()
                else:
                    body_text = shape.text_frame.text.strip()
        slide_titles.append({"pos": i + 1, "title": title_text, "body_preview": body_text[:300]})

    result["output_slide_count"] = len(prs.slides)
    result["output_titles"] = slide_titles

    # Find remaining Q2 references in titles
    q2_remaining = []
    for info in slide_titles:
        if "Q2 2024" in info["title"] or "Q2 2024" in info["body_preview"][:80]:
            q2_remaining.append({"pos": info["pos"], "title": info["title"]})
    result["q2_slides_remaining"] = q2_remaining

    # Find competitor slides
    competitor_slides = []
    for info in slide_titles:
        if "Apex Digital" in info["title"] or "APXD" in info["body_preview"]:
            competitor_slides.append({"pos": info["pos"], "title": info["title"]})
    result["competitor_slide_titles"] = competitor_slides

    # Check for Forward-Looking Statements slide (ideally at position 2)
    fls_pos = None
    fls_title = ""
    fls_body = ""
    for info in slide_titles:
        if "forward-looking" in info["title"].lower() or "forward looking" in info["title"].lower():
            fls_pos = info["pos"]
            fls_title = info["title"]
            fls_body = info["body_preview"]
            break
    result["fls_slide_position"] = fls_pos
    result["fls_slide_title"] = fls_title
    result["fls_body_text"] = fls_body

except Exception as e:
    result["error"] = "Error reading output file: " + str(e)

# Check original file unchanged
try:
    orig = Presentation(ORIGINAL_PPTX)
    result["original_slide_count"] = len(orig.slides)
    if orig.slides:
        for shape in orig.slides[0].shapes:
            if hasattr(shape, "placeholder_format") and shape.placeholder_format is not None:
                if shape.placeholder_format.idx == 0:
                    result["original_first_title"] = shape.text_frame.text.strip()
                    break
    result["original_unchanged"] = (len(orig.slides) == 30)
except Exception as e:
    result["original_unchanged"] = False
    result["original_slide_count"] = -1

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Output file: {result['output_exists']}, {result['output_slide_count']} slides")
print(f"Q2 references remaining: {len(result['q2_slides_remaining'])}")
print(f"Competitor slides remaining: {len(result['competitor_slide_titles'])}")
print(f"FLS disclaimer at position: {result['fls_slide_position']}")
print(f"Original unchanged: {result['original_unchanged']} ({result['original_slide_count']} slides)")
PYEOF

echo "=== Export complete: ${RESULT_FILE} ==="
