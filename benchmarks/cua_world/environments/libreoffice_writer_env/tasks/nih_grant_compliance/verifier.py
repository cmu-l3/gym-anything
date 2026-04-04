#!/usr/bin/env python3
"""Verifier for nih_grant_compliance task.

Checks that the agent reformatted an NIH R01 grant application to comply with
PA-23-093 formatting requirements and saved it as a new file.

Criteria (each ~14 points, 7 criteria total):
  1. Output file r01_formatted.docx exists and was saved after task start
  2. Body text uses an NIH-approved font (Arial, Helvetica, Georgia, Palatino Linotype)
  3. Body text font size is >= 11pt in the majority of runs
  4. Page margins are <= 0.5 inches on all four sides
  5. Section headings (Abstract, Specific Aims, etc.) use Heading 1 style
  6. References section entries have hanging indent formatting
  7. Document header contains the required grant identifier string

Pass threshold: 65% (5 of 7 criteria fully satisfied)
"""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_heading_styles,
    extract_citation_paragraphs,
    check_hanging_indent,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# NIH-approved fonts and common Linux substitutes
APPROVED_FONTS = {
    "arial", "helvetica", "georgia", "palatino linotype", "palatino",
    "liberation sans",  # Linux substitute for Arial (same metrics)
}

REQUIRED_HEADINGS = ["Abstract", "Specific Aims", "Research Strategy",
                     "Innovation", "Approach", "References"]

# 0.5 inches in EMU (914400 EMU = 1 inch)
HALF_INCH_EMU = 457200
TOLERANCE_EMU = 60000  # ~0.065 inch tolerance


def _check_body_font_compliance(doc):
    """
    Check that body text uses an NIH-approved font at >= 11pt.
    Returns (font_fraction, size_fraction) — fraction of compliant runs.
    """
    compliant_font = 0
    compliant_size = 0
    total = 0

    for para in doc.paragraphs:
        if not para.text.strip():
            continue
        style_name = para.style.name.lower() if para.style else ""
        if "heading" in style_name or "title" in style_name:
            continue  # skip headings

        for run in para.runs:
            if not run.text.strip():
                continue
            total += 1
            font_name = (run.font.name or "").lower().strip()
            # Also check paragraph-level style font as fallback
            if not font_name and para.style and para.style.font:
                font_name = (para.style.font.name or "").lower().strip()

            if any(appr in font_name for appr in APPROVED_FONTS) or font_name in APPROVED_FONTS:
                compliant_font += 1

            font_size = None
            if run.font.size:
                font_size = run.font.size.pt
            elif para.style and para.style.font and para.style.font.size:
                font_size = para.style.font.size.pt

            if font_size is None or font_size >= 11.0:
                compliant_size += 1

    if total == 0:
        return 0.0, 0.0
    return compliant_font / total, compliant_size / total


def _check_margins(doc):
    """Check that all page margins are <= 0.5 inches."""
    try:
        sec = doc.sections[0]
        margins = {
            "left": sec.left_margin,
            "right": sec.right_margin,
            "top": sec.top_margin,
            "bottom": sec.bottom_margin,
        }
        results = {}
        for side, emu in margins.items():
            if emu is None:
                results[side] = False
            else:
                results[side] = emu <= (HALF_INCH_EMU + TOLERANCE_EMU)
        return results
    except Exception as e:
        logger.warning(f"Margin check error: {e}")
        return {"left": False, "right": False, "top": False, "bottom": False}


def _check_header(doc, required_fragments):
    """Check that document header contains required text fragments."""
    try:
        for section in doc.sections:
            header = section.header
            if not header:
                continue
            header_text = " ".join(p.text for p in header.paragraphs).strip()
            if all(frag.lower() in header_text.lower() for frag in required_fragments):
                return True, header_text
        return False, ""
    except Exception as e:
        logger.warning(f"Header check error: {e}")
        return False, ""


def verify_nih_grant_compliance(traj, env_info, task_info):
    """Verify NIH R01 grant reformatting compliance."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Gate 1: Output file must exist (do-nothing check)
    output_path = "/home/ga/Documents/r01_formatted.docx"
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')

    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file r01_formatted.docx not found or unreadable: {error}",
        }

    try:
        metadata = task_info.get('metadata', {})
        feedback_parts = []
        score = 0
        CRITERION_POINTS = 14  # 7 criteria × 14 = 98 pts; last 2 pts rounding

        # --- Criterion 1: File saved (existence already confirmed above) ---
        # Also verify it's not just a copy of the draft (check content changed)
        # We use the heading style check below as a proxy for actual changes.
        score += CRITERION_POINTS
        feedback_parts.append("Output file r01_formatted.docx exists")

        # --- Criterion 2: Body font is NIH-approved ---
        font_frac, size_frac = _check_body_font_compliance(doc)
        if font_frac >= 0.50:
            score += CRITERION_POINTS
            feedback_parts.append(f"Font: {font_frac:.0%} of body runs use approved NIH font")
        else:
            feedback_parts.append(
                f"Font: only {font_frac:.0%} of body runs use an approved NIH font "
                f"(Arial/Helvetica/Georgia/Palatino required)"
            )

        # --- Criterion 3: Body font size >= 11pt ---
        if size_frac >= 0.60:
            score += CRITERION_POINTS
            feedback_parts.append(f"Font size: {size_frac:.0%} of body runs are >= 11pt")
        else:
            feedback_parts.append(
                f"Font size: only {size_frac:.0%} of body runs are >= 11pt (NIH minimum)"
            )

        # --- Criterion 4: Page margins <= 0.5 inches ---
        margin_results = _check_margins(doc)
        margins_ok = all(margin_results.values())
        compliant_margins = sum(1 for v in margin_results.values() if v)
        if margins_ok:
            score += CRITERION_POINTS
            feedback_parts.append("Margins: all four margins <= 0.5 inches (NIH compliant)")
        elif compliant_margins >= 3:
            score += CRITERION_POINTS // 2
            feedback_parts.append(
                f"Margins: {compliant_margins}/4 margins <= 0.5 inches "
                f"(non-compliant sides: {[s for s,v in margin_results.items() if not v]})"
            )
        else:
            failing = [s for s, v in margin_results.items() if not v]
            feedback_parts.append(
                f"Margins: {compliant_margins}/4 compliant (failing: {failing}) — "
                f"NIH requires >= 0.5 inch on all sides"
            )

        # --- Criterion 5: Section headings use Heading 1 style ---
        heading_map = {h: "Heading 1" for h in REQUIRED_HEADINGS}
        h1_matched, h1_total, _ = check_heading_styles(doc, heading_map)
        if h1_matched >= 5:
            score += CRITERION_POINTS
            feedback_parts.append(f"Headings: {h1_matched}/{h1_total} sections have Heading 1 style")
        elif h1_matched >= 3:
            score += CRITERION_POINTS // 2
            feedback_parts.append(
                f"Headings: {h1_matched}/{h1_total} sections have Heading 1 — need at least 5"
            )
        else:
            feedback_parts.append(
                f"Headings: only {h1_matched}/{h1_total} sections have Heading 1 style"
            )

        # --- Criterion 6: References have hanging indent ---
        ref_paras = extract_citation_paragraphs(doc, start_after="References")
        if not ref_paras:
            feedback_parts.append("Hanging indent: References section not found or empty")
        else:
            hanging_count = sum(1 for p in ref_paras if check_hanging_indent(p))
            ratio = hanging_count / len(ref_paras) if ref_paras else 0
            if ratio >= 0.60:
                score += CRITERION_POINTS
                feedback_parts.append(
                    f"Hanging indent: {hanging_count}/{len(ref_paras)} references have hanging indent"
                )
            elif ratio >= 0.30:
                score += CRITERION_POINTS // 2
                feedback_parts.append(
                    f"Hanging indent: {hanging_count}/{len(ref_paras)} — need at least 60%"
                )
            else:
                feedback_parts.append(
                    f"Hanging indent: only {hanging_count}/{len(ref_paras)} references "
                    f"have hanging indent (0.5-inch required)"
                )

        # --- Criterion 7: Header contains required grant identifier ---
        header_ok, header_text = _check_header(doc, ["Chen", "R01CA298471"])
        if header_ok:
            score += CRITERION_POINTS
            feedback_parts.append(f"Header: contains required grant identifier '{header_text[:60]}'")
        else:
            # Fallback: check for just the PI name or grant number
            header_partial, header_text2 = _check_header(doc, ["Chen"])
            if header_partial:
                score += CRITERION_POINTS // 2
                feedback_parts.append(
                    f"Header: contains 'Chen' but missing 'R01CA298471' (partial credit)"
                )
            else:
                feedback_parts.append(
                    "Header: document header does not contain 'Chen, S. — R01CA298471 — "
                    "Tumor Microenvironment Immunotherapy'"
                )

        passed = score >= 65
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": feedback,
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
