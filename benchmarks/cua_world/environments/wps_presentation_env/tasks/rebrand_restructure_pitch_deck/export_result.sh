#!/bin/bash
echo "=== Exporting rebrand_restructure_pitch_deck results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/rebrand_restructure_end_screenshot.png

OUTPUT_PPTX='/home/ga/Documents/presentations/meridian_pitch_final.pptx'
ORIGINAL_PPTX='/home/ga/Documents/presentations/apex_pitch_deck.pptx'
RESULT_FILE='/tmp/rebrand_restructure_result.json'

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

OLD_NAME = "Apex Consulting Partners"
NEW_NAME = "Meridian Strategy Group"
OLD_EMAIL = "contact@apexconsulting.com"
NEW_EMAIL = "contact@meridianstrategy.com"
FOOTER_TEXT = "CONFIDENTIAL"
FOOTER_FULL = "Meridian Strategy Group 2024"

result = {
    "output_exists": False,
    "output_slide_count": 0,
    "output_mtime": 0,
    "output_titles": [],

    # Rebrand checks
    "old_name_occurrences": [],
    "new_name_count": 0,
    "old_email_found": False,
    "new_email_found": False,

    # Table corrections (Case Study: Revenue Impact)
    "case_study_table_found": False,
    "case_study_table_slide_pos": 0,
    "case_study_table_cells": {},

    # Slide reordering (Our Team)
    "our_team_positions": [],

    # New slide (At a Glance)
    "at_a_glance_found": False,
    "at_a_glance_pos": 0,
    "at_a_glance_has_table": False,
    "at_a_glance_table_cells": {},

    # Footer
    "footer_slide_count": 0,
    "footer_full_match_count": 0,
    "footer_total_checked": 0,
    "title_slide_has_footer": False,

    # Original file
    "original_slide_count": 0,
    "original_unchanged": False,

    "error": None,
}

if not os.path.exists(OUTPUT_PPTX):
    result["error"] = "Output file not found at " + OUTPUT_PPTX
    with open('${RESULT_FILE}', 'w') as f:
        json.dump(result, f, indent=2)
    raise SystemExit(0)

result["output_exists"] = True
result["output_mtime"] = int(os.path.getmtime(OUTPUT_PPTX))

def get_all_text(slide):
    """Get all text from all shapes on a slide."""
    texts = []
    for shape in slide.shapes:
        if shape.has_text_frame:
            texts.append(shape.text_frame.text)
        if shape.has_table:
            for row in shape.table.rows:
                for cell in row.cells:
                    texts.append(cell.text)
    return " ".join(texts)

def get_title(slide):
    for shape in slide.shapes:
        try:
            pf = shape.placeholder_format
            if pf is not None and pf.idx == 0 and shape.has_text_frame:
                return shape.text_frame.text.strip()
        except (ValueError, AttributeError):
            pass
    return ""

def get_body_text(slide):
    texts = []
    for shape in slide.shapes:
        try:
            pf = shape.placeholder_format
            if pf is not None and pf.idx != 0 and shape.has_text_frame:
                texts.append(shape.text_frame.text.strip())
                continue
        except (ValueError, AttributeError):
            pass
        if shape.has_text_frame:
            t = shape.text_frame.text.strip()
            if t:
                texts.append(t)
    return "\n".join(texts)

try:
    prs = Presentation(OUTPUT_PPTX)
    result["output_slide_count"] = len(prs.slides)

    slide_titles = []
    old_name_found = []
    new_name_count = 0
    old_email_found = False
    new_email_found = False
    our_team_positions = []
    at_a_glance_found = False
    at_a_glance_pos = 0
    footer_count = 0
    footer_full_count = 0
    footer_checked = 0
    title_slide_footer = False

    for i, slide in enumerate(prs.slides):
        pos = i + 1
        title = get_title(slide)
        body = get_body_text(slide)
        all_text = get_all_text(slide)

        slide_titles.append({
            "pos": pos,
            "title": title,
            "body_preview": body[:300]
        })

        # --- Rebrand checks ---
        if OLD_NAME in all_text:
            old_name_found.append({"pos": pos, "context": title[:80]})
        if NEW_NAME in all_text:
            new_name_count += 1
        if OLD_EMAIL in all_text.lower():
            old_email_found = True
        if NEW_EMAIL in all_text.lower():
            new_email_found = True

        # --- Our Team position check ---
        if title.startswith("Our Team:"):
            our_team_positions.append({"title": title, "pos": pos})

        # --- At a Glance check ---
        title_lower = title.lower()
        if "at a glance" in title_lower or ("meridian" in title_lower and "glance" in title_lower):
            at_a_glance_found = True
            at_a_glance_pos = pos
            # Check for table on this slide
            for shape in slide.shapes:
                if shape.has_table:
                    result["at_a_glance_has_table"] = True
                    tbl = shape.table
                    rows = len(tbl.rows)
                    cols = len(tbl.columns)
                    cells = {}
                    headers = [tbl.cell(0, c).text.strip() for c in range(cols)]
                    for r in range(1, rows):
                        row_label = tbl.cell(r, 0).text.strip()
                        for c in range(1, cols):
                            col_header = headers[c] if c < len(headers) else f"col{c}"
                            cells[f"{row_label},{col_header}"] = tbl.cell(r, c).text.strip()
                    result["at_a_glance_table_cells"] = cells
                    break

        # --- Case Study table check ---
        if "case study" in title_lower and "revenue" in title_lower:
            result["case_study_table_slide_pos"] = pos
            for shape in slide.shapes:
                if shape.has_table:
                    result["case_study_table_found"] = True
                    tbl = shape.table
                    rows = len(tbl.rows)
                    cols = len(tbl.columns)
                    cells = {}
                    headers = [tbl.cell(0, c).text.strip() for c in range(cols)]
                    for r in range(1, rows):
                        row_label = tbl.cell(r, 0).text.strip()
                        for c in range(1, cols):
                            col_header = headers[c] if c < len(headers) else f"col{c}"
                            cells[f"{row_label},{col_header}"] = tbl.cell(r, c).text.strip()
                    result["case_study_table_cells"] = cells
                    break

        # --- Footer check (skip title slide = slide 1) ---
        if pos > 1:
            footer_checked += 1
            for shape in slide.shapes:
                if shape.has_text_frame:
                    txt = shape.text_frame.text
                    if FOOTER_TEXT in txt:
                        footer_count += 1
                        if FOOTER_FULL in txt:
                            footer_full_count += 1
                        break
        else:
            # Check if title slide incorrectly has footer
            for shape in slide.shapes:
                if shape.has_text_frame:
                    if FOOTER_TEXT in shape.text_frame.text:
                        title_slide_footer = True
                        break

    result["output_titles"] = slide_titles
    result["old_name_occurrences"] = old_name_found
    result["new_name_count"] = new_name_count
    result["old_email_found"] = old_email_found
    result["new_email_found"] = new_email_found
    result["our_team_positions"] = our_team_positions
    result["at_a_glance_found"] = at_a_glance_found
    result["at_a_glance_pos"] = at_a_glance_pos
    result["footer_slide_count"] = footer_count
    result["footer_full_match_count"] = footer_full_count
    result["footer_total_checked"] = footer_checked
    result["title_slide_has_footer"] = title_slide_footer

except Exception as e:
    result["error"] = "Error reading output file: " + str(e)

# Check original file unchanged
try:
    orig = Presentation(ORIGINAL_PPTX)
    result["original_slide_count"] = len(orig.slides)
    result["original_unchanged"] = (len(orig.slides) == 25)
except Exception as e:
    result["original_unchanged"] = False
    result["original_slide_count"] = -1

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Output: {result['output_slide_count']} slides, exists={result['output_exists']}")
print(f"Old name occurrences: {len(result['old_name_occurrences'])}")
print(f"New name count: {result['new_name_count']}")
print(f"Case study table found: {result['case_study_table_found']}")
print(f"Our Team positions: {result['our_team_positions']}")
print(f"At a Glance: found={result['at_a_glance_found']} pos={result['at_a_glance_pos']} table={result['at_a_glance_has_table']}")
print(f"Footer: {result['footer_slide_count']}/{result['footer_total_checked']} slides")
print(f"Original unchanged: {result['original_unchanged']} ({result['original_slide_count']} slides)")
PYEOF

echo "=== Export complete: ${RESULT_FILE} ==="
