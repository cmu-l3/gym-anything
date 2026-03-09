#!/usr/bin/env python3
"""Verifier for engineering_inspection_report task.

Checks that the agent formatted a structural engineering inspection report
per professional PE standards.

Criteria (each ~14 points, 7 criteria total = 98 pts):
  1. Output file inspection_report.docx exists
  2. Section headings use Heading 1 style (at least 5 of 7 headings)
  3. Observations formatted as 3-column tables with OBS-NNN labels (at least 4 of 7)
  4. Calculation section has 4-column tables (at least 2 of 3 calculations)
  5. Figure captions have 'Caption' style or contain 'Figure' prefix with numbering
  6. PE Certification section is enclosed in a bordered table with PE license number
  7. PE license number TX-78234 and certification statement present

Pass threshold: 65%
"""

import sys
import os
import logging
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_heading_styles,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SECTION_HEADINGS = [
    "Introduction", "Scope of Assessment", "Building Description",
    "Structural Observations", "Structural Calculations",
    "Conclusions and Recommendations", "Professional Engineer Certification",
]


def _check_observation_tables(doc):
    """
    Check if structural observations are formatted as tables with OBS labels.
    Returns (count_obs_tables, obs_table_details)
    """
    obs_tables = []
    obs_label_pattern = re.compile(r'OBS-\d{3}', re.IGNORECASE)

    # Check tables in the document for observation content
    for table in doc.tables:
        table_text = " ".join(cell.text for row in table.rows for cell in row.cells)
        # Look for observation-related keywords
        has_location = "location" in table_text.lower()
        has_deficiency = "deficiency" in table_text.lower() or "description" in table_text.lower()
        has_action = "action" in table_text.lower() or "recommended" in table_text.lower()

        if has_location and (has_deficiency or has_action):
            col_count = len(table.columns)
            obs_tables.append({
                "cols": col_count,
                "text_preview": table_text[:80],
                "has_3_cols": col_count >= 3,
            })

    # Also check paragraphs for OBS-NNN labels before tables
    obs_labels_found = []
    for para in doc.paragraphs:
        if obs_label_pattern.search(para.text):
            obs_labels_found.append(para.text.strip()[:40])

    return obs_tables, obs_labels_found


def _check_calculation_tables(doc):
    """
    Check if calculation section has 4-column tables with Parameter/Value/Unit/Code Reference.
    Returns (count_calc_tables, details)
    """
    calc_tables = []
    CALC_KEYWORDS = {"parameter", "value", "unit", "code reference", "reference"}

    for table in doc.tables:
        if len(table.rows) == 0:
            continue
        # Check header row for calculation keywords
        if table.rows:
            header_text = " ".join(cell.text.lower() for cell in table.rows[0].cells)
            keyword_matches = sum(1 for kw in CALC_KEYWORDS if kw in header_text)
            col_count = len(table.columns)

            if keyword_matches >= 2 and col_count >= 3:
                calc_tables.append({
                    "cols": col_count,
                    "header": header_text[:60],
                    "rows": len(table.rows),
                    "is_4_col": col_count >= 4,
                })

    return calc_tables


def _check_figure_captions(doc):
    """
    Check if figure captions use 'Caption' style or contain 'Figure N:' format.
    Returns (count_caption_style, count_figure_prefix, total_figure_refs)
    """
    caption_style_count = 0
    figure_prefix_count = 0
    total_figure_refs = 0

    figure_pattern = re.compile(r'figure\s+\d+', re.IGNORECASE)

    for para in doc.paragraphs:
        text = para.text.strip()
        style_name = (para.style.name or "").lower() if para.style else ""

        # Check for Caption style
        if "caption" in style_name and figure_pattern.search(text):
            caption_style_count += 1

        # Check for Figure N: pattern (with or without Caption style)
        if figure_pattern.search(text):
            total_figure_refs += 1
            # A formatted caption should be short (not the full paragraph text)
            if (
                text.lower().startswith("figure") and
                len(text) < 200 and
                re.match(r'figure\s+\d+', text, re.IGNORECASE)
            ):
                figure_prefix_count += 1

    return caption_style_count, figure_prefix_count, total_figure_refs


def _check_pe_certification(doc):
    """
    Check if PE Certification section has:
    - License number TX-78234
    - Certification statement
    - Enclosed in a bordered table
    """
    has_license = False
    has_statement = False
    in_table = False
    full_text = get_document_text(doc)

    # Check for PE license number
    has_license = "tx-78234" in full_text.lower() or "tx 78234" in full_text.lower()

    # Check for certification statement
    has_statement = "i hereby certify" in full_text.lower() or "hereby certify" in full_text.lower()

    # Check if PE certification is in a table
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                cell_text = cell.text.lower()
                if ("tx-78234" in cell_text or "hereby certify" in cell_text or
                        "pe license" in cell_text):
                    in_table = True
                    break

    return has_license, has_statement, in_table


def verify_engineering_inspection_report(traj, env_info, task_info):
    """Verify engineering inspection report formatting."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    output_path = "/home/ga/Documents/inspection_report.docx"
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')

    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file inspection_report.docx not found or unreadable: {error}",
        }

    try:
        feedback_parts = []
        score = 0
        POINTS = 14

        # --- Criterion 1: File exists ---
        score += POINTS
        feedback_parts.append("Output file inspection_report.docx exists")

        # --- Criterion 2: Section headings use Heading 1 style ---
        heading_map = {h: "Heading 1" for h in SECTION_HEADINGS}
        h1_matched, h1_total, _ = check_heading_styles(doc, heading_map)
        if h1_matched >= 5:
            score += POINTS
            feedback_parts.append(
                f"Section headings: {h1_matched}/{h1_total} have Heading 1 style"
            )
        elif h1_matched >= 3:
            score += POINTS // 2
            feedback_parts.append(
                f"Section headings: {h1_matched}/{h1_total} have Heading 1 (need at least 5)"
            )
        else:
            feedback_parts.append(
                f"Section headings: only {h1_matched}/{h1_total} have Heading 1 style. "
                f"Apply Heading 1 to all 7 major sections."
            )

        # --- Criterion 3: Observation tables (3 columns, OBS labels) ---
        obs_tables, obs_labels = _check_observation_tables(doc)
        obs_3col = sum(1 for t in obs_tables if t["has_3_cols"])
        obs_label_count = len(obs_labels)

        if obs_3col >= 4 or (obs_3col >= 2 and obs_label_count >= 4):
            score += POINTS
            feedback_parts.append(
                f"Observations: {obs_3col} 3-column tables found, "
                f"{obs_label_count} OBS-NNN labels found"
            )
        elif obs_3col >= 2 or obs_label_count >= 4:
            score += POINTS // 2
            feedback_parts.append(
                f"Observations: {obs_3col} 3-column tables and {obs_label_count} OBS labels "
                f"(need at least 4 of 7 as 3-column tables with OBS-NNN labels)"
            )
        else:
            feedback_parts.append(
                f"Observations: only {obs_3col} 3-column tables, {obs_label_count} OBS labels. "
                f"Each of 7 deficiency observations needs a 3-column table with Location/"
                f"Deficiency Description/Recommended Action columns."
            )

        # --- Criterion 4: Calculation tables (4 columns) ---
        calc_tables = _check_calculation_tables(doc)
        calc_4col = sum(1 for t in calc_tables if t["is_4_col"])

        if calc_4col >= 2:
            score += POINTS
            feedback_parts.append(
                f"Calculations: {calc_4col} 4-column tables with Parameter/Value/Unit/"
                f"Code Reference headers found"
            )
        elif len(calc_tables) >= 2:
            score += POINTS // 2
            feedback_parts.append(
                f"Calculations: {len(calc_tables)} tables found but only {calc_4col} have "
                f"4 columns — need Parameter, Value, Unit, Code Reference"
            )
        else:
            feedback_parts.append(
                f"Calculations: only {len(calc_tables)} calculation tables found. "
                f"3 calculations need 4-column tables (Parameter/Value/Unit/Code Reference)."
            )

        # --- Criterion 5: Figure captions with Caption style or Figure N: prefix ---
        caption_style, figure_prefix, total_fig_refs = _check_figure_captions(doc)
        if caption_style >= 4 or figure_prefix >= 4:
            score += POINTS
            feedback_parts.append(
                f"Figure captions: {caption_style} with Caption style, "
                f"{figure_prefix} with Figure N: prefix format "
                f"({total_fig_refs} total figure references)"
            )
        elif caption_style >= 2 or figure_prefix >= 2:
            score += POINTS // 2
            feedback_parts.append(
                f"Figure captions: {caption_style} Caption-styled, {figure_prefix} Figure N: "
                f"formatted — need at least 4 of 5 using Caption style or Figure N: format"
            )
        else:
            feedback_parts.append(
                f"Figure captions: only {caption_style} Caption-styled, {figure_prefix} "
                f"Figure N: formatted ({total_fig_refs} figure refs total). "
                f"Apply LibreOffice Caption style to all 5 figure captions."
            )

        # --- Criterion 6 & 7: PE Certification in bordered table with license ---
        has_license, has_statement, in_table = _check_pe_certification(doc)
        if in_table and has_license:
            score += POINTS
            feedback_parts.append(
                "PE Certification: enclosed in table with PE license TX-78234"
            )
        elif in_table or has_license:
            score += POINTS // 2
            feedback_parts.append(
                f"PE Certification: partial — in table: {in_table}, license TX-78234: {has_license}"
            )
        else:
            feedback_parts.append(
                "PE Certification: not in a bordered table or PE license TX-78234 not found. "
                "The certification section must be a bordered single-cell table."
            )

        if has_statement:
            score += POINTS
            feedback_parts.append(
                "PE Statement: 'I hereby certify' statement present in document"
            )
        else:
            feedback_parts.append(
                "PE Statement: 'I hereby certify that this structural assessment was prepared "
                "by me or under my direct supervision' not found in document"
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
