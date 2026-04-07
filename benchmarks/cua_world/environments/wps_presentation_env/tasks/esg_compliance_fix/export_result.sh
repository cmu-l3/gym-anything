#!/bin/bash
echo "=== Exporting esg_compliance_fix results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/esg_compliance_fix_end_screenshot.png

OUTPUT_PPTX='/home/ga/Documents/ESG_corrected.pptx'
ORIGINAL_PPTX='/home/ga/Documents/ESG_board_presentation.pptx'
RESULT_FILE='/tmp/esg_compliance_fix_result.json'

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

# Expected correct GRI codes (wrong → correct):
# Slide 7: "Emissions Disclosure (GRI 302-1)" → should say GRI 305-1
# Slide 10: "Energy Consumption Data (GRI 305-2)" → should say GRI 302-1 or 302-2
# Slide 15: "Water Withdrawal Data (GRI 401-3)" → should say GRI 303-3
WRONG_GRI_PAIRS = [
    ("emissions disclosure", "302-1", "305-1"),   # Scope 1 emissions should be GRI 305-1
    ("energy consumption data", "305-2", "302"),  # Energy consumption should be GRI 302
    ("water withdrawal data", "401-3", "303-3"),  # Water withdrawal should be GRI 303-3
]

MARKETING_KEYWORDS = [
    "testimonial", "great place to work", "why invest", "employee testimonials",
    "forbes best employers", "dividend growth", "revenue cagr"
]

TCFD_PILLAR_TITLES = [
    "tcfd pillar 1: governance",
    "tcfd pillar 2: strategy",
    "tcfd pillar 3: risk management",
    "tcfd pillar 4: metrics and targets",
]

result = {
    "output_exists": False,
    "output_slide_count": 0,
    "output_titles": [],
    "gri_errors_fixed": [],         # list of {"slide": title, "was_wrong": bool, "is_now_correct": bool}
    "gri_still_wrong": [],          # slides where GRI code still wrong
    "marketing_slides_remaining": [],
    "tcfd_order": [],               # actual positions (1-indexed) of the 4 TCFD slides
    "tcfd_order_correct": False,
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
    marketing_remaining = []
    tcfd_positions = {}  # pillar_name -> position 1-indexed

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
        slide_info = {"pos": i + 1, "title": title_text, "body_preview": body_text[:150]}
        slide_titles.append(slide_info)
        title_lower = title_text.lower()
        body_lower = body_text.lower()

        # Check marketing content
        combined = title_lower + " " + body_lower
        found_mkt = [kw for kw in MARKETING_KEYWORDS if kw in combined]
        if found_mkt:
            marketing_remaining.append({"pos": i + 1, "title": title_text, "keywords": found_mkt})

        # Track TCFD pillar positions
        for pillar_lower in TCFD_PILLAR_TITLES:
            if pillar_lower in title_lower:
                tcfd_positions[pillar_lower] = i + 1
                break

    result["output_slide_count"] = len(prs.slides)
    result["output_titles"] = slide_titles
    result["marketing_slides_remaining"] = marketing_remaining

    # Check GRI code corrections
    gri_still_wrong = []
    gri_errors_fixed = []
    for slide_info in slide_titles:
        t = slide_info["title"].lower()
        # Check each expected wrong pair
        for topic_kw, wrong_suffix, correct_prefix in WRONG_GRI_PAIRS:
            if topic_kw in t:
                if wrong_suffix in t:
                    gri_still_wrong.append({"pos": slide_info["pos"], "title": slide_info["title"],
                                            "problem": f"still has {wrong_suffix}, should be {correct_prefix}"})
                elif correct_prefix.split('-')[0] in t:  # GRI 305, GRI 302, GRI 303
                    gri_errors_fixed.append({"pos": slide_info["pos"], "title": slide_info["title"], "fixed": True})
    result["gri_errors_fixed"] = gri_errors_fixed
    result["gri_still_wrong"] = gri_still_wrong

    # Check TCFD order
    tcfd_order_positions = []
    for pillar_lower in TCFD_PILLAR_TITLES:
        pos = tcfd_positions.get(pillar_lower)
        tcfd_order_positions.append({"pillar": pillar_lower, "pos": pos})
    result["tcfd_order"] = tcfd_order_positions

    positions = [x["pos"] for x in tcfd_order_positions if x["pos"] is not None]
    if len(positions) == 4:
        result["tcfd_order_correct"] = (positions == sorted(positions))
    else:
        result["tcfd_order_correct"] = False

except Exception as e:
    result["error"] = "Error reading output: " + str(e)

# Check original unchanged
try:
    orig = Presentation(ORIGINAL_PPTX)
    result["original_slide_count"] = len(orig.slides)
    result["original_unchanged"] = (len(orig.slides) == 24)
except Exception:
    result["original_unchanged"] = False
    result["original_slide_count"] = -1

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Output: {result['output_slide_count']} slides")
print(f"GRI errors still wrong: {len(result['gri_still_wrong'])}")
print(f"Marketing slides remaining: {len(result['marketing_slides_remaining'])}")
print(f"TCFD order correct: {result['tcfd_order_correct']}")
print(f"TCFD positions: {[(x['pillar'][-15:], x['pos']) for x in result['tcfd_order']]}")
print(f"Original unchanged: {result['original_unchanged']}")
PYEOF

echo "=== Export complete: ${RESULT_FILE} ==="
