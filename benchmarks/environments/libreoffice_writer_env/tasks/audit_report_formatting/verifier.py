#!/usr/bin/env python3
"""Verifier for audit_report_formatting task.

Checks that the agent formatted an internal audit report according to
IIA standards and firm presentation requirements.

Criteria (each ~16 points, 6 criteria total = 96 pts):
  1. Output file audit_final.docx exists
  2. Executive Summary is enclosed in a bordered table cell
  3. Audit findings use Heading 2 style with 'Finding N:' prefix (3+ of 5)
  4. Risk Ratings table has a formatted header row (dark background)
  5. Risk ratings 'High'/'Medium'/'Low' have colored text in the table
  6. Footer contains the required report title text

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

FINDING_TITLES = [
    "Access Control Deficiencies",
    "Segregation of Duties Gaps",
    "Vendor Due Diligence Failures",
    "Data Retention Policy Violations",
    "IT Change Management Weaknesses",
]


def _check_executive_summary_boxed(doc):
    """
    Check if the Executive Summary section is enclosed in a bordered table.
    Returns (True if in table, detail string)
    """
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                cell_text = cell.text.lower()
                if "executive summary" in cell_text and len(cell_text) > 50:
                    # Executive summary text is inside a table cell — good
                    # Check for borders in the table XML
                    try:
                        xml = table._element.xml
                        # Table Grid style or tblBdr element indicates borders
                        has_border = (
                            'tblBorders' in xml or
                            'tblStyle' in xml or
                            'Table Grid' in xml or
                            'w:val="single"' in xml
                        )
                        return True, f"Executive Summary enclosed in table (bordered: {has_border})"
                    except Exception:
                        return True, "Executive Summary enclosed in table"
    return False, "Executive Summary not enclosed in a bordered table"


def _check_finding_headings(doc):
    """
    Check how many findings have 'Finding N:' prefixed headings with Heading 2 style.
    Returns (count_correct, total, detail_list)
    """
    correct = []
    missing = []

    for title in FINDING_TITLES:
        idx = FINDING_TITLES.index(title) + 1
        prefix = f"Finding {idx}"

        found_heading = False
        found_correct_style = False

        for para in doc.paragraphs:
            para_text = para.text.strip()
            if prefix.lower() in para_text.lower() and title.lower() in para_text.lower():
                found_heading = True
                style_name = (para.style.name or "").lower() if para.style else ""
                if "heading" in style_name:
                    found_correct_style = True
                    correct.append(f"{prefix}: {title[:30]}")
                    break
            elif title.lower() in para_text.lower():
                style_name = (para.style.name or "").lower() if para.style else ""
                if "heading" in style_name:
                    # Has heading style but missing 'Finding N:' prefix
                    missing.append(f"'{title[:30]}' has Heading style but no 'Finding {idx}:' prefix")
                    break

        if not found_heading:
            missing.append(f"'{title[:30]}' heading not found with 'Finding {idx}:' prefix")

    return correct, missing


def _check_risk_table_header_shading(doc):
    """
    Check if the risk ratings table has a shaded header row.
    Returns (has_dark_header, has_color_ratings, detail)
    """
    for table in doc.tables:
        # Find the table that has High/Medium/Low ratings
        table_text = " ".join(
            cell.text for row in table.rows for cell in row.cells
        )
        if "High" in table_text and "Medium" in table_text and "Low" in table_text:
            # Found the risk table
            has_dark_header = False
            has_color_ratings = False

            # Check header row for shading
            if len(table.rows) > 0:
                header_row = table.rows[0]
                try:
                    xml = header_row._element.xml
                    # Look for w:shd element with non-white color
                    shd_match = re.search(r'w:shd[^/]*/?\s*(?:w:fill|w:color)="([0-9A-Fa-f]+)"', xml)
                    if shd_match or 'w:shd' in xml:
                        color_val = shd_match.group(1) if shd_match else "found"
                        # Check it's not white (FFFFFF or auto)
                        if color_val.upper() not in ("FFFFFF", "AUTO", ""):
                            has_dark_header = True
                    # Also look for w:fill attribute
                    fill_match = re.search(r'w:fill="([0-9A-Fa-f]+)"', xml)
                    if fill_match:
                        fill_val = fill_match.group(1).upper()
                        if fill_val not in ("FFFFFF", "AUTO", ""):
                            has_dark_header = True
                except Exception:
                    pass

            # Check for colored text in risk rating cells
            try:
                from lxml import etree
                table_xml = table._element.xml
                # Look for color elements (w:color w:val="...") in the table
                color_matches = re.findall(r'w:color\s+w:val="([0-9A-Fa-f]+)"', table_xml)
                # Filter for non-black, non-auto colors
                meaningful_colors = [
                    c for c in color_matches
                    if c.upper() not in ("000000", "AUTO", "FFFFFF", "")
                ]
                if len(meaningful_colors) >= 2:
                    has_color_ratings = True
            except Exception:
                pass

            return has_dark_header, has_color_ratings, "Risk table found"

    return False, False, "Risk ratings table (High/Medium/Low) not found"


def _check_footer_content(doc, required_fragment="Internal Audit Report"):
    """Check footer for required text."""
    try:
        for section in doc.sections:
            footer = section.footer
            if not footer:
                continue
            footer_text = " ".join(p.text for p in footer.paragraphs).strip()
            if required_fragment.lower() in footer_text.lower():
                return True, footer_text
        return False, ""
    except Exception as e:
        logger.warning(f"Footer check error: {e}")
        return False, ""


def _check_signoff_boxed(doc):
    """Check if Report Sign-Off is in a bordered table."""
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                cell_text = cell.text.lower()
                if ("chief audit" in cell_text or "audit committee" in cell_text) and \
                   "date:" in cell_text:
                    return True, "Sign-off block enclosed in table"
    # Fallback: check as plain text
    full_text = get_document_text(doc)
    if "chief audit executive:" in full_text.lower() and "audit committee chair:" in full_text.lower():
        return False, "Sign-off keywords found but not in a table"
    return False, "Sign-off block not found"


def verify_audit_report_formatting(traj, env_info, task_info):
    """Verify internal audit report formatting."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    output_path = "/home/ga/Documents/audit_final.docx"
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')

    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file audit_final.docx not found or unreadable: {error}",
        }

    try:
        feedback_parts = []
        score = 0
        POINTS = 16

        # --- Criterion 1: File exists ---
        score += POINTS
        feedback_parts.append("Output file audit_final.docx exists")

        # --- Criterion 2: Executive Summary in bordered table ---
        exec_boxed, exec_detail = _check_executive_summary_boxed(doc)
        if exec_boxed:
            score += POINTS
            feedback_parts.append(f"Executive Summary: {exec_detail}")
        else:
            feedback_parts.append(
                f"Executive Summary: {exec_detail}. "
                f"Must be enclosed in a bordered single-cell table."
            )

        # --- Criterion 3: Finding headings with Heading 2 + 'Finding N:' prefix ---
        correct_findings, missing_findings = _check_finding_headings(doc)
        if len(correct_findings) >= 4:
            score += POINTS
            feedback_parts.append(
                f"Findings: {len(correct_findings)}/5 have correct 'Finding N:' prefix with Heading 2"
            )
        elif len(correct_findings) >= 2:
            score += POINTS // 2
            feedback_parts.append(
                f"Findings: {len(correct_findings)}/5 correctly formatted (need at least 4)"
            )
        else:
            feedback_parts.append(
                f"Findings: only {len(correct_findings)}/5 have 'Finding N:' prefix with Heading 2 style. "
                f"Issues: {'; '.join(missing_findings[:3])}"
            )

        # --- Criterion 4: Risk table has formatted header row (dark background) ---
        has_dark_header, has_color_ratings, risk_detail = _check_risk_table_header_shading(doc)
        if has_dark_header:
            score += POINTS
            feedback_parts.append(f"Risk table header: dark background shading applied")
        else:
            feedback_parts.append(
                f"Risk table header: no dark background shading detected. "
                f"Header row needs dark gray (#404040) background with bold white text. "
                f"({risk_detail})"
            )

        # --- Criterion 5: Colored risk rating text (High=red, Medium=orange, Low=green) ---
        if has_color_ratings:
            score += POINTS
            feedback_parts.append("Risk ratings: colored text found in Risk Rating column")
        else:
            feedback_parts.append(
                "Risk ratings: 'High', 'Medium', 'Low' text not colored "
                "(High=red, Medium=orange, Low=green required)"
            )

        # --- Criterion 6: Footer with required text ---
        footer_ok, footer_text = _check_footer_content(doc)
        if footer_ok:
            score += POINTS
            feedback_parts.append(
                f"Footer: contains 'Internal Audit Report' ('{footer_text[:60]}')"
            )
        else:
            feedback_parts.append(
                "Footer: does not contain 'Internal Audit Report — Q3 2024 | DRAFT'. "
                "A footer with report title and NorthBridge name is required."
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
