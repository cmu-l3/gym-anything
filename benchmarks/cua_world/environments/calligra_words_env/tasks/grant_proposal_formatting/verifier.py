#!/usr/bin/env python3
"""Verifier for the grant_proposal_formatting task."""

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


def verify_grant_proposal_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/nsf_proposal.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        criteria_passed = 0
        total_criteria = 10
        feedback_parts = []

        # ── 1. Cover page title formatted: bold and >= 14pt ─────────────
        proposal_title = metadata.get(
            "proposal_title",
            "Biochar-Amended Bioretention Systems for Enhanced Stormwater "
            "Treatment in Urban Watersheds",
        )
        title_pattern = re.escape(proposal_title)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)

        if title_bold and title_sized:
            criteria_passed += 1
            feedback_parts.append("Cover page title bold and >=14pt")
        else:
            missing = []
            if not title_bold:
                missing.append("bold")
            if not title_sized:
                missing.append(">=14pt")
            feedback_parts.append(f"Cover page title missing: {', '.join(missing)}")

        # ── 2. Cover page elements centered ─────────────────────────────
        pi_name = metadata.get("pi_name", "Dr. Elena Vasquez")
        institution = metadata.get("institution", "Pacific Northwest University")

        pi_centered, _ = check_paragraph_alignment_odt(
            content_tree, styles_tree, re.escape(pi_name), "center"
        )
        inst_centered, _ = check_paragraph_alignment_odt(
            content_tree, styles_tree, re.escape(institution), "center"
        )

        if pi_centered > 0 and inst_centered > 0:
            criteria_passed += 1
            feedback_parts.append("Cover page elements centered")
        else:
            missing = []
            if pi_centered == 0:
                missing.append("PI name")
            if inst_centered == 0:
                missing.append("institution")
            feedback_parts.append(f"Cover page not centered: {', '.join(missing)}")

        # ── 3. H1 section headings ──────────────────────────────────────
        section_headings = metadata.get("section_headings", [])
        h1_matched, h1_total, h1_details = check_heading_styles_odt(
            content_tree, styles_tree, section_headings, 1
        )
        if h1_matched >= 5:
            criteria_passed += 1
            feedback_parts.append(f"H1 headings: {h1_matched}/{h1_total}")
        else:
            feedback_parts.append(f"H1 headings too low: {h1_matched}/{h1_total}")

        # ── 4. H2 subsection headings ───────────────────────────────────
        all_subsections = (
            metadata.get("project_summary_subsections", [])
            + metadata.get("project_description_subsections", [])
        )
        h2_matched, h2_total, h2_details = check_heading_styles_odt(
            content_tree, styles_tree, all_subsections, 2
        )
        if h2_matched >= 5:
            criteria_passed += 1
            feedback_parts.append(f"H2 subsections: {h2_matched}/{h2_total}")
        else:
            feedback_parts.append(f"H2 subsections too low: {h2_matched}/{h2_total}")

        # ── 5. Body text justified ──────────────────────────────────────
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(sample), "justify"
            )
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Body paragraphs justified: {justified_count}/{len(body_samples)}")
        else:
            feedback_parts.append(
                f"Body paragraphs justified too low: {justified_count}/{len(body_samples)}"
            )

        # ── 6. Font size >= 11pt ────────────────────────────────────────
        font_ok_count = 0
        font_check_samples = body_samples[:3] if body_samples else []
        for sample in font_check_samples:
            if check_text_font_size_odt(content_tree, styles_tree, re.escape(sample), 11.0):
                font_ok_count += 1

        if font_check_samples and font_ok_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"Font size >=11pt: {font_ok_count}/{len(font_check_samples)}")
        else:
            feedback_parts.append(
                f"Font size check too low: {font_ok_count}/{len(font_check_samples)}"
            )

        # ── 7. Budget table exists ──────────────────────────────────────
        tables = get_odt_tables(content_tree)
        budget_table_found = False
        for table in tables:
            all_cells = " ".join(
                cell.lower() for row in table.get("rows", []) for cell in row
            )
            if any(
                kw in all_cells
                for kw in ["category", "year 1", "total", "senior personnel", "equipment"]
            ):
                budget_table_found = True
                break

        if budget_table_found:
            criteria_passed += 1
            feedback_parts.append("Budget table found")
        else:
            feedback_parts.append("Budget table not found")

        # ── 8. Table of Contents present ────────────────────────────────
        toc_found = detect_toc_odt(content_tree)
        if toc_found:
            criteria_passed += 1
            feedback_parts.append("Table of Contents detected")
        else:
            feedback_parts.append("Table of Contents not detected")

        # ── 9. Content preservation ─────────────────────────────────────
        full_text = get_document_text_odt(content_tree).lower()
        content_keywords = metadata.get("content_keywords", [])
        preserved = sum(1 for kw in content_keywords if kw.lower() in full_text)

        if content_keywords and preserved >= 6:
            criteria_passed += 1
            feedback_parts.append(f"Content preserved: {preserved}/{len(content_keywords)}")
        else:
            feedback_parts.append(
                f"Content preservation too low: {preserved}/{len(content_keywords)}"
            )

        # ── 10. VLM visual check ────────────────────────────────────────
        vlm_result = vlm_verify_screenshot(
            env_info,
            """
Analyze this Calligra Words screenshot of an NSF grant proposal and answer in JSON:
{
  "title_formatted": true/false,
  "headings_styled": true/false,
  "body_justified": true/false,
  "professional_layout": true/false
}
Judge only what is visible on screen. "title_formatted" means the proposal title
appears bold and larger than body text. "headings_styled" means section headings
are visually distinct. "body_justified" means body text has even left and right
margins. "professional_layout" means the document looks like a formal grant proposal.
""",
        )
        if vlm_result is not None:
            vlm_pass_count = sum(
                1
                for key in ("title_formatted", "headings_styled", "body_justified", "professional_layout")
                if vlm_result.get(key)
            )
            if vlm_pass_count >= 3:
                criteria_passed += 1
                feedback_parts.append(f"VLM confirmed formatting ({vlm_pass_count}/4 checks)")
            else:
                feedback_parts.append(f"VLM did not confirm formatting ({vlm_pass_count}/4 checks)")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM unavailable")

        score = int((criteria_passed / total_criteria) * 100)
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
