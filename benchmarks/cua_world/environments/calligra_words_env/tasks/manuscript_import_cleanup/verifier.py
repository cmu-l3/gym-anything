#!/usr/bin/env python3
"""Verifier for the manuscript_import_cleanup task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_italic_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_styles,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_manuscript_import_cleanup(traj, env_info, task_info):
    """Verify that all formatting errors in the Frankenstein manuscript have been fixed."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/frankenstein_manuscript.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []

        # ----------------------------------------------------------------
        # Criterion 1: All chapter headings are Heading 1
        # Check all 6 headings (Letter 1-4, Chapter 1-2).
        # Pass if >= 5/6 are Heading 1.
        # ----------------------------------------------------------------
        chapter_headings = metadata.get("chapter_headings", [
            "Letter 1", "Letter 2", "Letter 3", "Letter 4",
            "Chapter 1", "Chapter 2",
        ])
        h1_matched, h1_total, h1_details = check_heading_styles_odt(
            content_tree, styles_tree, chapter_headings, 1,
        )
        if h1_matched >= 5:
            criteria_passed += 1
            feedback_parts.append(f"Headings as H1: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(
                f"Headings as H1: {h1_matched}/{h1_total} (need >=5). "
                + "; ".join(h1_details)
            )

        # ----------------------------------------------------------------
        # Criterion 2: No wrong-font paragraphs remain
        # Check that none of the 4 known error paragraphs still use a wrong
        # font (Comic Sans MS or Courier New).
        # Pass if 0 wrong-font paragraphs found among the 4.
        # ----------------------------------------------------------------
        wrong_font_paragraphs = metadata.get("error_paragraphs_wrong_font", [])
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)

        wrong_font_count = 0
        for wf_text in wrong_font_paragraphs:
            for para in paragraphs:
                if wf_text.lower() in para['text'].lower():
                    style_name = para.get('style_name', '')
                    # Walk the style chain to find font_name
                    font_name = _resolve_font_name(styles, style_name)
                    if font_name and ("comic" in font_name.lower() or "courier" in font_name.lower()):
                        wrong_font_count += 1
                    break

        if wrong_font_count == 0:
            criteria_passed += 1
            feedback_parts.append("Wrong fonts fixed: all 4 paragraphs OK")
        else:
            feedback_parts.append(f"Wrong fonts remaining: {wrong_font_count}/4 still have wrong font")

        # ----------------------------------------------------------------
        # Criterion 3: Body text justified
        # Check 3 sample paragraphs. Pass if >= 2/3 are justified.
        # ----------------------------------------------------------------
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(sample), "justify",
            )
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"Body justified: {justified_count}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body justified: {justified_count}/{len(body_samples)} (need >=2)")

        # ----------------------------------------------------------------
        # Criterion 4: Italic phrases restored
        # Check each of the 5 should-be-italic phrases. Pass if >= 4/5.
        # ----------------------------------------------------------------
        italic_phrases = metadata.get("should_be_italic_phrases", [])
        italic_count = 0
        italic_details = []
        for phrase in italic_phrases:
            is_italic = check_text_italic_odt(
                content_tree, styles_tree, re.escape(phrase),
            )
            if is_italic:
                italic_count += 1
                italic_details.append(f"'{phrase}': italic OK")
            else:
                italic_details.append(f"'{phrase}': NOT italic")

        if italic_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"Italics restored: {italic_count}/{len(italic_phrases)} OK")
        else:
            feedback_parts.append(
                f"Italics restored: {italic_count}/{len(italic_phrases)} (need >=4). "
                + "; ".join(italic_details)
            )

        # ----------------------------------------------------------------
        # Criterion 5: Incorrect bold removed
        # Check that the 3 incorrectly-bolded words are NOT bold.
        # Pass if <= 1 is still bold.
        # ----------------------------------------------------------------
        bolded_words = metadata.get("incorrectly_bolded_words", [])
        still_bold_count = 0
        bold_details = []
        for word in bolded_words:
            is_bold = check_text_bold_odt(
                content_tree, styles_tree, re.escape(word),
            )
            if is_bold:
                still_bold_count += 1
                bold_details.append(f"'{word}': still bold")
            else:
                bold_details.append(f"'{word}': not bold OK")

        if still_bold_count <= 1:
            criteria_passed += 1
            feedback_parts.append(
                f"Incorrect bold removed: {len(bolded_words) - still_bold_count}/{len(bolded_words)} fixed"
            )
        else:
            feedback_parts.append(
                f"Incorrect bold: {still_bold_count}/{len(bolded_words)} still bold (need <=1). "
                + "; ".join(bold_details)
            )

        # ----------------------------------------------------------------
        # Criterion 6: Consistent font size (~12pt for body paragraphs)
        # Sample 3 body paragraphs and check they have at least 11pt.
        # ----------------------------------------------------------------
        font_size_samples = body_samples  # reuse the same 3 samples
        font_ok_count = 0
        for sample in font_size_samples:
            has_size = check_text_font_size_odt(
                content_tree, styles_tree, re.escape(sample), 11.0,
            )
            if has_size:
                font_ok_count += 1

        if font_size_samples and font_ok_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"Font size ~12pt: {font_ok_count}/{len(font_size_samples)} OK")
        else:
            feedback_parts.append(
                f"Font size ~12pt: {font_ok_count}/{len(font_size_samples)} (need >=2)"
            )

        # ----------------------------------------------------------------
        # Criterion 7: Content preservation
        # Check 6 keywords present in document text. Pass if >= 5/6.
        # ----------------------------------------------------------------
        full_text = get_document_text_odt(content_tree).lower()
        content_keywords = metadata.get("content_keywords", [])
        preserved = sum(1 for keyword in content_keywords if keyword.lower() in full_text)

        if content_keywords and preserved >= 5:
            criteria_passed += 1
            feedback_parts.append(f"Content preserved: {preserved}/{len(content_keywords)} keywords found")
        else:
            missing_kw = [kw for kw in content_keywords if kw.lower() not in full_text]
            feedback_parts.append(
                f"Content preserved: {preserved}/{len(content_keywords)} (need >=5). "
                f"Missing: {missing_kw}"
            )

        # ----------------------------------------------------------------
        # Criterion 8: VLM visual check
        # ----------------------------------------------------------------
        vlm_result = vlm_verify_screenshot(env_info, """
Analyze this Calligra Words screenshot showing a manuscript document.
Answer in JSON:
{
  "headings_formatted": true/false,
  "body_text_justified": true/false,
  "consistent_font": true/false,
  "professional_appearance": true/false
}
Check if the document appears to have properly formatted headings (bold, large),
justified body text with consistent font, and an overall professional manuscript appearance.
Judge only what is visible on screen.
""")
        if vlm_result is not None:
            vlm_pass = (
                vlm_result.get("headings_formatted")
                and vlm_result.get("body_text_justified")
            ) or (
                vlm_result.get("consistent_font")
                and vlm_result.get("professional_appearance")
            )
            if vlm_pass:
                criteria_passed += 1
                feedback_parts.append("VLM confirmed proper manuscript formatting visually")
            else:
                feedback_parts.append("VLM did not confirm expected formatting")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM unavailable, skipping visual check")

        # ----------------------------------------------------------------
        # Final score
        # ----------------------------------------------------------------
        score = int((criteria_passed / total_criteria) * 100) if total_criteria > 0 else 0
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
        }
    except Exception as exc:
        logger.error("Verification failed", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {exc}"}
    finally:
        cleanup_verification_temp(temp_dir)


def _resolve_font_name(styles, style_name):
    """Walk up the style chain to find the font_name property."""
    seen = set()
    current = style_name
    while current and current not in seen:
        seen.add(current)
        style = styles.get(current)
        if not style:
            break
        font_name = style.get('font_name', '')
        if font_name:
            return font_name
        current = style.get('parent', '')
    return ''
