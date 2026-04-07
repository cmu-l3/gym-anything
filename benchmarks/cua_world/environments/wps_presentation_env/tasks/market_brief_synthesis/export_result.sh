#!/bin/bash
echo "=== Exporting market_brief_synthesis results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/market_brief_synthesis_end_screenshot.png

OUTPUT_PPTX='/home/ga/Documents/EV_brief_corrected.pptx'
ORIGINAL_PPTX='/home/ga/Documents/EV_market_brief.pptx'
RESULT_FILE='/tmp/market_brief_synthesis_result.json'

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

# Required order for first 10 EV slides (titles, lowercased for fuzzy match)
REQUIRED_ORDER = [
    "executive summary",
    "us ev market size and growth",
    "ev adoption by segment",
    "key oem market share",
    "battery technology landscape",
    "charging infrastructure build-out",
    "consumer purchase intent drivers",
    "policy environment: ira and state incentives",
    "competitive threat: chinese oems",
    "12-month outlook and risks",
]

PHARMA_KEYWORDS = ["pharma", "pharmaceutical", "drug", "wholesaler", "specialty drug",
                   "cold chain", "biosimilar", "340b", "gpo", "dispensing"]

result = {
    "output_exists": False,
    "output_slide_count": 0,
    "output_titles": [],
    "pharma_slides_remaining": [],
    "first_10_order_score": 0,    # 0-10: how many of first 10 slots match required order
    "first_10_actual_titles": [],
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

try:
    prs = Presentation(OUTPUT_PPTX)
    slide_titles = []
    pharma_remaining = []

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
        combined = (title_text + " " + body_text).lower()
        found_kw = [kw for kw in PHARMA_KEYWORDS if kw in combined]
        if found_kw:
            pharma_remaining.append({"pos": i + 1, "title": title_text, "keywords": found_kw})

    result["output_slide_count"] = len(prs.slides)
    result["output_titles"] = slide_titles
    result["pharma_slides_remaining"] = pharma_remaining

    # Score slide order: check how many of the first 10 slots match required order
    first_10 = slide_titles[:10]
    result["first_10_actual_titles"] = [s["title"] for s in first_10]
    order_score = 0
    for i, req_title in enumerate(REQUIRED_ORDER):
        if i < len(first_10):
            actual = first_10[i]["title"].lower().strip()
            if req_title in actual or actual in req_title:
                order_score += 1
    result["first_10_order_score"] = order_score

except Exception as e:
    result["error"] = "Error reading output: " + str(e)

# Check original unchanged
try:
    orig = Presentation(ORIGINAL_PPTX)
    result["original_slide_count"] = len(orig.slides)
    result["original_unchanged"] = (len(orig.slides) == 20)
except Exception as e:
    result["original_unchanged"] = False
    result["original_slide_count"] = -1

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Output: {result['output_slide_count']} slides")
print(f"Pharma slides remaining: {len(result['pharma_slides_remaining'])}")
print(f"Slide order score: {result['first_10_order_score']}/10")
print(f"Original unchanged: {result['original_unchanged']}")
PYEOF

echo "=== Export complete: ${RESULT_FILE} ==="
