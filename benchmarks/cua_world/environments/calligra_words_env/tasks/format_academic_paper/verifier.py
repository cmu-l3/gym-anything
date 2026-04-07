#!/usr/bin/env python3
"""Verifier for the format_academic_paper task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    check_text_italic_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_format_academic_paper(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/origin_of_species.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []

        title_pattern = rf"^{re.escape(metadata.get('title', 'On the Origin of Species'))}$"
        author_pattern = rf"^{re.escape(metadata.get('authors', 'Charles Darwin'))}$"

        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)

        if title_centered > 0 and title_bold and title_sized:
            criteria_passed += 1
            feedback_parts.append("Title formatted correctly")
        else:
            missing = []
            if title_centered == 0:
                missing.append("centered")
            if not title_bold:
                missing.append("bold")
            if not title_sized:
                missing.append(">=16pt")
            feedback_parts.append(f"Title missing: {', '.join(missing)}")

        author_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, author_pattern, "center")
        author_italic = check_text_italic_odt(content_tree, styles_tree, author_pattern)

        if author_centered > 0 and author_italic:
            criteria_passed += 1
            feedback_parts.append("Author line centered and italic")
        else:
            missing = []
            if author_centered == 0:
                missing.append("centered")
            if not author_italic:
                missing.append("italic")
            feedback_parts.append(f"Author line missing: {', '.join(missing)}")

        h1_matched, h1_total, _ = check_heading_styles_odt(
            content_tree,
            styles_tree,
            metadata.get("section_headings", []),
            1,
        )
        if h1_matched >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Heading 1 sections: {h1_matched}/{h1_total}")
        else:
            feedback_parts.append(f"Heading 1 sections too low: {h1_matched}/{h1_total}")

        h2_matched, h2_total, _ = check_heading_styles_odt(
            content_tree,
            styles_tree,
            metadata.get("subsection_headings", []),
            2,
        )
        if h2_matched >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Heading 2 subsections: {h2_matched}/{h2_total}")
        else:
            feedback_parts.append(f"Heading 2 subsections too low: {h2_matched}/{h2_total}")

        justified_count = 0
        body_samples = metadata.get("body_alignment_samples", [])
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(
                content_tree,
                styles_tree,
                re.escape(sample),
                "justify",
            )
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Body paragraphs justified: {justified_count}/{len(body_samples)}")
        else:
            feedback_parts.append(f"Body paragraphs justified too low: {justified_count}/{len(body_samples)}")

        full_text = get_document_text_odt(content_tree).lower()
        content_keywords = metadata.get("content_keywords", [])
        preserved = sum(1 for keyword in content_keywords if keyword.lower() in full_text)
        if content_keywords and preserved >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Content preserved: {preserved}/{len(content_keywords)}")
        else:
            feedback_parts.append(f"Content preservation too low: {preserved}/{len(content_keywords)}")

        vlm_result = vlm_verify_screenshot(env_info, """
Analyze this Calligra Words screenshot and answer in JSON:
{
  "title_formatted": true,
  "author_formatted": true,
  "headings_visible": true,
  "body_justified": true
}
Judge only what is visible on screen.
""")
        if vlm_result is not None:
            if (
                vlm_result.get("title_formatted")
                and vlm_result.get("author_formatted")
                and vlm_result.get("headings_visible")
            ) or (
                vlm_result.get("headings_visible")
                and vlm_result.get("body_justified")
            ):
                criteria_passed += 1
                feedback_parts.append("VLM confirmed academic formatting visually")
            else:
                feedback_parts.append("VLM did not confirm the expected formatting")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM unavailable")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

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
