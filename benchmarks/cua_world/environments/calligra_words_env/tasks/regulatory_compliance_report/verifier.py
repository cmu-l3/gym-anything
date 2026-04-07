#!/usr/bin/env python3
"""Verifier for the regulatory_compliance_report task."""

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
    cleanup_verification_temp,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_tables,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_regulatory_compliance_report(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/phase1_esa_report.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        criteria_passed = 0
        total_criteria = 10
        feedback_parts = []

        # ── Criterion 1: Title formatting (bold, >=16pt) ──
        title_text = metadata.get("title_text", "Phase I Environmental Site Assessment")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)

        if title_bold and title_sized:
            criteria_passed += 1
            feedback_parts.append("Title: bold and >=16pt OK")
        else:
            missing = []
            if not title_bold:
                missing.append("bold")
            if not title_sized:
                missing.append(">=16pt")
            feedback_parts.append(f"Title missing: {', '.join(missing)}")

        # ── Criterion 2: Project name formatting (bold) ──
        project_text = metadata.get("project_text", "Riverside Industrial Complex")
        project_pattern = re.escape(project_text)
        project_bold = check_text_bold_odt(content_tree, styles_tree, project_pattern)

        if project_bold:
            criteria_passed += 1
            feedback_parts.append("Project name: bold OK")
        else:
            feedback_parts.append("Project name: not bold")

        # ── Criterion 3: Heading 1 styles (at least 6 of 8 sections) ──
        esa_sections = metadata.get("esa_sections", [])
        h1_matched, h1_total, h1_details = check_heading_styles_odt(
            content_tree, styles_tree, esa_sections, 1,
        )
        if h1_matched >= 6:
            criteria_passed += 1
            feedback_parts.append(f"Heading 1: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(f"Heading 1: only {h1_matched}/{h1_total} (need 6)")

        # ── Criterion 4: Heading 2 styles (at least 5 of 9 subsections) ──
        esa_subsections = metadata.get("esa_subsections", [])
        h2_matched, h2_total, h2_details = check_heading_styles_odt(
            content_tree, styles_tree, esa_subsections, 2,
        )
        if h2_matched >= 5:
            criteria_passed += 1
            feedback_parts.append(f"Heading 2: {h2_matched}/{h2_total} OK")
        else:
            feedback_parts.append(f"Heading 2: only {h2_matched}/{h2_total} (need 5)")

        # ── Criterion 5: Body text justified (at least 3 of 5 samples) ──
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(sample), "justify",
            )
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Body justified: {justified_count}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body justified: only {justified_count}/{len(body_samples)} (need 3)")

        # ── Criterion 6: Font size ~12pt for body text ──
        font_size_ok = 0
        for sample in body_samples:
            sized = check_text_font_size_odt(
                content_tree, styles_tree, re.escape(sample), 11.0,
            )
            if sized:
                font_size_ok += 1

        if body_samples and font_size_ok >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Body font size: {font_size_ok}/{len(body_samples)} >= 11pt OK")
        else:
            feedback_parts.append(f"Body font size: only {font_size_ok}/{len(body_samples)} >= 11pt (need 3)")

        # ── Criterion 7: Table of Contents present ──
        toc_present = detect_toc_odt(content_tree)
        if toc_present:
            criteria_passed += 1
            feedback_parts.append("Table of Contents: present")
        else:
            feedback_parts.append("Table of Contents: not found")

        # ── Criterion 8: At least 1 table exists ──
        tables = get_odt_tables(content_tree)
        if len(tables) > 0:
            criteria_passed += 1
            feedback_parts.append(f"Tables: {len(tables)} found")
        else:
            feedback_parts.append("Tables: none found (expected at least 1)")

        # ── Criterion 9: Content preservation (at least 6 of 8 keywords) ──
        full_text = get_document_text_odt(content_tree).lower()
        content_keywords = metadata.get("content_keywords", [])
        preserved = sum(1 for kw in content_keywords if kw.lower() in full_text)

        if content_keywords and preserved >= 6:
            criteria_passed += 1
            feedback_parts.append(f"Content preserved: {preserved}/{len(content_keywords)} OK")
        else:
            feedback_parts.append(f"Content preserved: only {preserved}/{len(content_keywords)} (need 6)")

        # ── Criterion 10: VLM visual verification ──
        vlm_result = vlm_verify_screenshot(env_info, """
Analyze this Calligra Words screenshot of a Phase I Environmental Site Assessment report and answer in JSON:
{
  "title_formatted": true/false,
  "headings_styled": true/false,
  "body_justified": true/false,
  "professional_layout": true/false
}
- title_formatted: Is there a large, bold title visible?
- headings_styled: Are section headings visually distinct from body text (larger, bold)?
- body_justified: Does body text appear justified (even left and right edges)?
- professional_layout: Does the document look like a professionally formatted report?
Judge only what is visible on screen.
""")
        if vlm_result is not None:
            vlm_pass_count = sum(1 for k in (
                "title_formatted", "headings_styled", "body_justified", "professional_layout"
            ) if vlm_result.get(k))
            if vlm_pass_count >= 3:
                criteria_passed += 1
                feedback_parts.append(f"VLM: {vlm_pass_count}/4 visual checks passed")
            else:
                feedback_parts.append(f"VLM: only {vlm_pass_count}/4 visual checks passed")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable, reducing total criteria")

        # ── Scoring ──
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
