#!/bin/bash
echo "=== Exporting research_deck_prep results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/research_deck_prep_end_screenshot.png

OUTPUT_PPTX='/home/ga/Documents/AI_research_corrected.pptx'
OUTPUT_PDF='/home/ga/Documents/AI_research_corrected.pdf'
ORIGINAL_PPTX='/home/ga/Documents/AI_research_overview.pptx'
RESULT_FILE='/tmp/research_deck_prep_result.json'

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
OUTPUT_PDF = '${OUTPUT_PDF}'
ORIGINAL_PPTX = '${ORIGINAL_PPTX}'

# Wrong citation info
WRONG_CITATIONS = [
    ("bert", "devlin", "2019", "2018"),   # BERT: 2019 is wrong, 2018 is correct
    ("gpt-3", "brown", "2021", "2020"),   # GPT-3: 2021 is wrong, 2020 is correct
    ("llama", "touvron", "2022", "2023"), # LLaMA: 2022 is wrong, 2023 is correct
]

VISION_KEYWORDS = [
    "imagenet", "imagesynth", "dall-e 2", "stable diffusion", "latent diffusion",
    "image synthesis", "computer vision benchmark", "diffusion model for image"
]

result = {
    "output_pptx_exists": False,
    "output_slide_count": 0,
    "output_titles": [],
    "citation_errors_remaining": [],  # list of {slide, author, wrong_year, still_present}
    "citation_errors_fixed": [],
    "vision_slides_remaining": [],
    "pdf_exists": False,
    "pdf_size_bytes": 0,
    "pdf_mtime": 0,
    "original_slide_count": 0,
    "original_unchanged": False,
    "output_mtime": 0,
    "error": None,
}

if not os.path.exists(OUTPUT_PPTX):
    result["error"] = "Output PPTX not found at " + OUTPUT_PPTX
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f, indent=2)
    raise SystemExit(0)

result["output_pptx_exists"] = True
result["output_mtime"] = int(os.path.getmtime(OUTPUT_PPTX))

# Check PDF
result["pdf_exists"] = os.path.exists(OUTPUT_PDF)
if result["pdf_exists"]:
    result["pdf_size_bytes"] = os.path.getsize(OUTPUT_PDF)
    result["pdf_mtime"] = int(os.path.getmtime(OUTPUT_PDF))

try:
    prs = Presentation(OUTPUT_PPTX)
    slide_titles = []
    vision_remaining = []
    citation_errors_remaining = []
    citation_errors_fixed = []

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
        slide_info = {"pos": i + 1, "title": title_text, "body_preview": body_text[:250]}
        slide_titles.append(slide_info)
        combined = (title_text + " " + body_text).lower()

        # Check vision content
        found_vision = [kw for kw in VISION_KEYWORDS if kw in combined]
        if found_vision:
            vision_remaining.append({"pos": i + 1, "title": title_text, "keywords": found_vision})

        # Check citation years
        for paper_kw, author_kw, wrong_year, correct_year in WRONG_CITATIONS:
            if paper_kw in combined and author_kw in combined:
                if wrong_year in combined:
                    citation_errors_remaining.append({
                        "pos": i + 1,
                        "title": title_text,
                        "paper": paper_kw.upper(),
                        "wrong_year": wrong_year,
                        "correct_year": correct_year
                    })
                elif correct_year in combined:
                    citation_errors_fixed.append({
                        "pos": i + 1,
                        "title": title_text,
                        "paper": paper_kw.upper(),
                        "correct_year": correct_year
                    })

    result["output_slide_count"] = len(prs.slides)
    result["output_titles"] = slide_titles
    result["vision_slides_remaining"] = vision_remaining
    result["citation_errors_remaining"] = citation_errors_remaining
    result["citation_errors_fixed"] = citation_errors_fixed

except Exception as e:
    result["error"] = "Error reading output: " + str(e)

# Check original unchanged
try:
    orig = Presentation(ORIGINAL_PPTX)
    result["original_slide_count"] = len(orig.slides)
    result["original_unchanged"] = (len(orig.slides) == 22)
except Exception:
    result["original_unchanged"] = False
    result["original_slide_count"] = -1

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Output PPTX: {result['output_slide_count']} slides")
print(f"Citation errors remaining: {len(result['citation_errors_remaining'])}")
print(f"Vision slides remaining: {len(result['vision_slides_remaining'])}")
print(f"PDF exists: {result['pdf_exists']} ({result['pdf_size_bytes']} bytes)")
print(f"Original unchanged: {result['original_unchanged']}")
PYEOF

echo "=== Export complete: ${RESULT_FILE} ==="
