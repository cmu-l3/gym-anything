#!/usr/bin/env python3
"""Verifier for format_research_paper task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_heading_styles,
    check_text_formatting,
    check_paragraph_alignment,
    check_hanging_indent,
    extract_citation_paragraphs,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_research_paper_formatting(traj, env_info, task_info):
    """
    Verify that the research paper was formatted correctly.

    Checks:
    1. Title is centered, bold, and ~16pt
    2. Authors line is centered and italic
    3. Section headings have Heading 1 style
    4. Subsection headings have Heading 2 style
    5. Body text paragraphs are justified
    6. Reference entries have hanging indent
    7. Content is preserved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/raw_paper.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        metadata = task_info.get('metadata', {})
        section_headings = metadata.get('section_headings', [])
        subsection_headings = metadata.get('subsection_headings', [])
        title_text = metadata.get('title_text', 'Regional Climate Variability')
        authors_text = metadata.get('authors_text', 'Hansen')

        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []

        # Criterion 1: Title is centered and bold
        title_centered = check_paragraph_alignment(doc, title_text, 'center')
        title_bold = check_text_formatting(doc, title_text, bold=True)

        if title_centered and title_bold:
            criteria_passed += 1
            feedback_parts.append("Title: centered and bold")
        elif title_bold:
            feedback_parts.append("Title: bold but not centered")
        elif title_centered:
            feedback_parts.append("Title: centered but not bold")
        else:
            feedback_parts.append("Title: not formatted correctly")

        # Criterion 2: Authors are centered and italic
        authors_centered = check_paragraph_alignment(doc, authors_text, 'center')
        authors_italic = check_text_formatting(doc, authors_text, italic=True)

        if authors_centered and authors_italic:
            criteria_passed += 1
            feedback_parts.append("Authors: centered and italic")
        elif authors_italic:
            feedback_parts.append("Authors: italic but not centered")
        elif authors_centered:
            feedback_parts.append("Authors: centered but not italic")
        else:
            feedback_parts.append("Authors: not formatted correctly")

        # Criterion 3: Section headings have Heading 1
        section_map = {h: 'Heading 1' for h in section_headings}
        h1_matched, h1_total, h1_feedback = check_heading_styles(doc, section_map)

        if h1_matched >= 5:  # At least 5 of 7
            criteria_passed += 1
            feedback_parts.append(f"Section headings: {h1_matched}/{h1_total} correct")
        else:
            feedback_parts.append(
                f"Section headings: only {h1_matched}/{h1_total} have Heading 1"
            )

        # Criterion 4: Subsection headings have Heading 2
        subsection_map = {h: 'Heading 2' for h in subsection_headings}
        h2_matched, h2_total, h2_feedback = check_heading_styles(doc, subsection_map)

        if h2_matched >= 3:  # At least 3 of 4
            criteria_passed += 1
            feedback_parts.append(f"Subsection headings: {h2_matched}/{h2_total} correct")
        else:
            feedback_parts.append(
                f"Subsection headings: only {h2_matched}/{h2_total} have Heading 2"
            )

        # Criterion 5: Body text justified
        # Check a few representative body paragraphs
        justified_count = 0
        body_samples = [
            "temperature anomalies",
            "warming trend",
            "climate variability",
            "precipitation patterns",
        ]
        for sample in body_samples:
            if check_paragraph_alignment(doc, sample, 'justify'):
                justified_count += 1

        if justified_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"Body text justified: {justified_count}/{len(body_samples)} checked")
        else:
            feedback_parts.append(f"Body text not justified: only {justified_count}/{len(body_samples)}")

        # Criterion 6: References have hanging indent
        ref_paragraphs = extract_citation_paragraphs(doc, start_after="References")
        hanging_count = 0
        for para in ref_paragraphs:
            if check_hanging_indent(para):
                hanging_count += 1

        if len(ref_paragraphs) > 0 and hanging_count >= len(ref_paragraphs) * 0.6:
            criteria_passed += 1
            feedback_parts.append(f"Hanging indent: {hanging_count}/{len(ref_paragraphs)} references")
        else:
            feedback_parts.append(
                f"Hanging indent: only {hanging_count}/{len(ref_paragraphs)} references"
            )

        # Criterion 7: Content preserved
        full_text = get_document_text(doc).lower()
        key_phrases = [
            "mann-kendall",
            "0.16 degrees celsius per decade",
            "global historical climatology network",
            "extreme heat events",
        ]
        preserved = sum(1 for p in key_phrases if p in full_text)
        if preserved >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Content preserved: {preserved}/{len(key_phrases)}")
        else:
            feedback_parts.append(f"Content may be corrupted: {preserved}/{len(key_phrases)}")

        # Criterion 8: VLM cross-validation (visual check of final screenshot)
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this LibreOffice Writer screenshot. Answer in JSON:
{
    "has_formatted_title": true/false,
    "has_styled_headings": true/false,
    "text_appears_justified": true/false,
    "has_academic_structure": true/false
}
Does the document show:
1. A formatted title (centered, bold, larger text at the top)?
2. Styled section headings (visually distinct from body text)?
3. Body text that appears justified (aligned on both left and right margins)?
4. Overall academic paper structure (title, sections, references)?
""")
        if vlm_result is not None:
            has_title = vlm_result.get("has_formatted_title", False)
            has_headings = vlm_result.get("has_styled_headings", False)
            has_structure = vlm_result.get("has_academic_structure", False)
            if (has_title and has_headings) or (has_headings and has_structure):
                criteria_passed += 1
                feedback_parts.append("VLM: academic formatting confirmed visually")
            else:
                feedback_parts.append("VLM: academic formatting not confirmed visually")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable (skipped)")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 71  # 5/7 or 6/8 with VLM

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
