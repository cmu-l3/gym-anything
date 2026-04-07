#!/usr/bin/env python3
"""Verifier for the soil_survey_report_formatting task."""

import logging
import os
import re
import sys

# Import Calligra verification utilities provided by the environment
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
    get_odt_page_layout,
    get_odt_paragraphs,
    get_odt_styles,
)

# Fallback VLM query if not in utils
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_soil_survey_report_formatting(traj, env_info, task_info):
    """Verify that the soil survey report has been formatted according to requirements."""
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/soil_survey_report.odt")

    # Copy and parse the document
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []

        # Ensure document isn't empty/deleted
        full_text = get_document_text_odt(content_tree)
        if len(full_text.strip()) < 1000:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Document appears to be empty or significantly truncated."
            }

        # ── Criterion 1: Title formatting (bold, >=14pt) - 10 points ──
        title_text = metadata.get("title_text", "Soil Survey and Management Assessment")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)

        if title_bold and title_sized:
            score += 10
            feedback_parts.append("Title: bold and >=14pt OK")
        else:
            missing = []
            if not title_bold: missing.append("bold")
            if not title_sized: missing.append(">=14pt")
            feedback_parts.append(f"Title formatting missing: {', '.join(missing)}")

        # ── Criterion 2: Heading 1 styles (at least 5 of 7 sections) - 15 points ──
        expected_h1 = metadata.get("expected_h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(
            content_tree, styles_tree, expected_h1, 1,
        )
        if h1_matched >= 5:
            score += 15
            feedback_parts.append(f"H1 Sections: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(f"H1 Sections: only {h1_matched}/{h1_total} (need 5)")

        # ── Criterion 3: Heading 2 styles (at least 3 of 5 subsections) - 10 points ──
        expected_h2 = metadata.get("expected_h2_subsections", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(
            content_tree, styles_tree, expected_h2, 2,
        )
        if h2_matched >= 3:
            score += 10
            feedback_parts.append(f"H2 Subsections: {h2_matched}/{h2_total} OK")
        else:
            feedback_parts.append(f"H2 Subsections: only {h2_matched}/{h2_total} (need 3)")

        # ── Criterion 4: Tables exist (at least 2 tables with >=2 rows) - 15 points ──
        tables = get_odt_tables(content_tree)
        valid_tables = [tbl for tbl in tables if len(tbl.get("rows", [])) >= 2]
        
        if len(valid_tables) >= 2:
            score += 15
            feedback_parts.append(f"Tables: {len(valid_tables)} valid tables found OK")
        elif len(valid_tables) == 1:
            score += 5  # Partial credit
            feedback_parts.append(f"Tables: only {len(valid_tables)} valid table found (need 2)")
        else:
            feedback_parts.append("Tables: No valid tables found")

        # ── Criterion 5: Body text justified (at least 2 of 3 samples) - 10 points ──
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(sample), "justify",
            )
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 2:
            score += 10
            feedback_parts.append(f"Body justified: {justified_count}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body justified: only {justified_count}/{len(body_samples)} (need 2)")

        # ── Criterion 6: Body font size >= 11pt - 5 points ──
        font_size_ok = 0
        for sample in body_samples:
            sized = check_text_font_size_odt(
                content_tree, styles_tree, re.escape(sample), 11.0,
            )
            if sized:
                font_size_ok += 1

        if body_samples and font_size_ok >= 2:
            score += 5
            feedback_parts.append(f"Body font size: {font_size_ok}/{len(body_samples)} >= 11pt OK")
        else:
            feedback_parts.append(f"Body font size: only {font_size_ok}/{len(body_samples)} >= 11pt (need 2)")

        # ── Criterion 7: Table of Contents present - 10 points ──
        has_toc = detect_toc_odt(content_tree)
        if has_toc:
            score += 10
            feedback_parts.append("Table of Contents: Present OK")
        else:
            feedback_parts.append("Table of Contents: Missing")

        # ── Criterion 8: Content preservation - 10 points ──
        content_keywords = metadata.get("content_keywords", [])
        full_text_lower = full_text.lower()
        keyword_hits = sum(1 for kw in content_keywords if kw.lower() in full_text_lower)
        
        if keyword_hits >= 6:
            score += 10
            feedback_parts.append(f"Content preservation: {keyword_hits}/{len(content_keywords)} keywords OK")
        else:
            feedback_parts.append(f"Content preservation: {keyword_hits}/{len(content_keywords)} keywords (too much deleted)")

        # ── Criterion 9: Page layout defined (margins) - 5 points ──
        layouts = get_odt_page_layout(content_tree, styles_tree)
        margins_defined = False
        for layout_name, props in layouts.items():
            if any(k in props for k in ['margin_top', 'margin_bottom', 'margin_left', 'margin_right']):
                margins_defined = True
                break

        if margins_defined:
            score += 5
            feedback_parts.append("Page layout: Margins defined OK")
        else:
            feedback_parts.append("Page layout: Default margins unchanged")

        # ── Criterion 10: VLM Visual Verification - 10 points ──
        if query_vlm:
            try:
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                
                vlm_prompt = (
                    "You are verifying the formatting of a soil survey report in Calligra Words. "
                    "Does the document look like a professionally formatted technical report? "
                    "Look for the following across the images:\n"
                    "1. Is there a clear heading hierarchy (bold/larger text for sections)?\n"
                    "2. Are there visible tables containing data (not just plain text columns)?\n"
                    "3. Are paragraphs properly blocked (justified) and easy to read?\n"
                    "Respond with a JSON object: {\"professional_formatting\": true/false, \"tables_visible\": true/false, \"reason\": \"...\"}"
                )
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames + [final])
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    is_professional = parsed.get("professional_formatting", False)
                    tables_visible = parsed.get("tables_visible", False)
                    
                    if is_professional and tables_visible:
                        score += 10
                        feedback_parts.append("VLM visual verification: Passed")
                    else:
                        feedback_parts.append(f"VLM visual verification: Failed. {parsed.get('reason', '')}")
                else:
                    feedback_parts.append("VLM visual verification: Error during inference")
            except Exception as e:
                logger.error(f"VLM verification error: {e}")
                feedback_parts.append("VLM visual verification: Error during evaluation")
        else:
            feedback_parts.append("VLM visual verification: Not available")

        # Check for Structural Minimum (must have done *both* headings and tables)
        if h1_matched == 0 and len(valid_tables) == 0:
            score = 0
            feedback_parts.append("FAIL: No structural changes detected (do-nothing check).")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        cleanup_verification_temp(temp_dir)