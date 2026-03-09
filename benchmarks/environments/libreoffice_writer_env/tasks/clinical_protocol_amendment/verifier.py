#!/usr/bin/env python3
"""Verifier for clinical_protocol_amendment task.

Checks that the agent correctly amended a clinical trial protocol document
per DSMB safety recommendations.

Criteria (each ~14 points, 7 criteria total = 98 pts):
  1. Output file protocol_v2.docx exists
  2. Document header updated from Version 1.0 to Version 2.0
  3. Old stopping rule 'two (2) or more' replaced with 'one (1) or more'
  4. Original stopping rule 'two (2) or more' no longer present
  5. New QTc exclusion criterion added (containing '450 ms' or 'QTc')
  6. New Section 9.4 heading exists with 'Cardiac Safety Monitoring' content
  7. Version history table has a new row for Version 2.0

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
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_header_version(doc, new_version="Version 2.0", new_date="15 March 2024"):
    """Check that the document header was updated to Version 2.0."""
    try:
        for section in doc.sections:
            header = section.header
            if not header:
                continue
            header_text = " ".join(p.text for p in header.paragraphs).strip()
            has_v2 = new_version.lower() in header_text.lower()
            has_new_date = new_date.lower() in header_text.lower() or "march 2024" in header_text.lower()
            has_old_v1 = "version 1.0" in header_text.lower()

            return has_v2, has_new_date, has_old_v1, header_text
    except Exception as e:
        logger.warning(f"Header check error: {e}")
    return False, False, False, ""


def _check_stopping_rule(doc):
    """
    Check whether the stopping rule was updated:
    - 'one (1) or more' should be present
    - 'two (2) or more' in context of cardiac events should NOT be present
    """
    full_text = get_document_text(doc)

    # Check for the new stopping rule
    has_new_rule = "one (1) or more" in full_text.lower()

    # Check that the OLD stopping rule is not present in the cardiac context
    # (allow "two" elsewhere, but not in the stopping rule sentence)
    old_rule_in_context = False
    for para in doc.paragraphs:
        t = para.text.lower()
        if "two (2) or more" in t and ("cardiac" in t or "grade 3" in t or "stopping" in t):
            old_rule_in_context = True
            break

    return has_new_rule, old_rule_in_context


def _check_qtc_exclusion(doc):
    """Check that a new QTc exclusion criterion was added."""
    full_text = get_document_text(doc).lower()
    has_qtc = (
        "qtc" in full_text and (
            "450" in full_text or
            "470" in full_text or
            "screening qtc" in full_text or
            "qtc interval" in full_text
        )
    )
    # Also check that it appears in the context of exclusion criteria
    for para in doc.paragraphs:
        t = para.text.lower()
        if ("qtc" in t or "qt interval" in t) and ("450" in t or "470" in t or "ms" in t):
            return True, para.text[:100]
    if has_qtc:
        return True, "(QTc mentioned in document)"
    return False, ""


def _check_new_section_94(doc):
    """Check for new Section 9.4 with 'Cardiac Safety Monitoring Plan' heading and content."""
    has_heading = False
    has_content = False
    heading_style_ok = False

    for para in doc.paragraphs:
        text = para.text.strip()
        # Check for the section heading
        if "cardiac safety monitoring" in text.lower() and "9.4" in text:
            has_heading = True
            style_name = (para.style.name or "").lower() if para.style else ""
            heading_style_ok = "heading" in style_name
        # Check for the content
        if "12-lead ecg" in text.lower() and ("assessment" in text.lower() or "screening" in text.lower()):
            has_content = True

    # Also check if content exists even if heading format is slightly different
    if not has_heading:
        for para in doc.paragraphs:
            text = para.text.strip()
            if "cardiac safety monitoring" in text.lower() and (
                "plan" in text.lower() or "9.4" in text or len(text) < 60
            ):
                has_heading = True
                style_name = (para.style.name or "").lower() if para.style else ""
                heading_style_ok = "heading" in style_name
                break

    return has_heading, has_content, heading_style_ok


def _check_version_history_table(doc):
    """Check if the version history table has a new row for Version 2.0."""
    for table in doc.tables:
        table_text = " ".join(
            cell.text for row in table.rows for cell in row.cells
        ).lower()
        if "version" in table_text and ("1.0" in table_text or "initial" in table_text):
            # This is the version history table
            has_v2_row = "2.0" in table_text
            has_amendment_desc = (
                "amendment" in table_text or
                "cardiac" in table_text or
                "qtc" in table_text or
                "dsmb" in table_text
            )
            return has_v2_row, has_amendment_desc, len(table.rows)
    return False, False, 0


def verify_clinical_protocol_amendment(traj, env_info, task_info):
    """Verify clinical trial protocol amendment changes."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    output_path = "/home/ga/Documents/protocol_v2.docx"
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')

    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file protocol_v2.docx not found or unreadable: {error}",
        }

    try:
        feedback_parts = []
        score = 0
        POINTS = 14

        # --- Criterion 1: File exists ---
        score += POINTS
        feedback_parts.append("Output file protocol_v2.docx exists")

        # --- Criterion 2: Header updated to Version 2.0 and new date ---
        has_v2, has_new_date, has_old_v1, header_text = _check_header_version(doc)
        if has_v2 and has_new_date:
            score += POINTS
            feedback_parts.append(
                f"Header: updated to Version 2.0 and March 2024 ('{header_text[:70]}')"
            )
        elif has_v2:
            score += POINTS // 2
            feedback_parts.append(
                f"Header: Version 2.0 present but date not updated to '15 March 2024'"
            )
        elif has_old_v1:
            feedback_parts.append(
                f"Header: still shows 'Version 1.0' — must be changed to 'Version 2.0'"
            )
        else:
            feedback_parts.append(
                f"Header: version update not detected ('{header_text[:60]}')"
            )

        # --- Criterion 3: New stopping rule 'one (1) or more' present ---
        has_new_rule, old_rule_present = _check_stopping_rule(doc)
        if has_new_rule:
            score += POINTS
            feedback_parts.append(
                "Stopping rule: 'one (1) or more' found in Section 8 — correct amendment"
            )
        else:
            feedback_parts.append(
                "Stopping rule: 'one (1) or more' NOT found in document — "
                "must replace 'two (2) or more' with 'one (1) or more' in Section 8.2"
            )

        # --- Criterion 4: Old stopping rule 'two (2) or more' removed from cardiac context ---
        if has_new_rule and not old_rule_present:
            score += POINTS
            feedback_parts.append(
                "Stopping rule: old 'two (2) or more' language correctly removed from cardiac context"
            )
        elif old_rule_present:
            feedback_parts.append(
                "Stopping rule: 'two (2) or more' still present in cardiac stopping rule context — "
                "must be replaced with 'one (1) or more'"
            )
        else:
            # No new rule and no old rule — not sure what happened
            feedback_parts.append(
                "Stopping rule: neither old nor new rule found in cardiac context"
            )

        # --- Criterion 5: New QTc exclusion criterion added ---
        has_qtc, qtc_text = _check_qtc_exclusion(doc)
        if has_qtc:
            score += POINTS
            feedback_parts.append(
                f"QTc exclusion criterion: added to Section 5 ('{qtc_text[:80]}')"
            )
        else:
            feedback_parts.append(
                "QTc exclusion criterion: NOT found — must add "
                "'Screening QTc interval greater than 450 ms (males) or 470 ms (females)' "
                "to Section 5.2 exclusion list"
            )

        # --- Criterion 6: New Section 9.4 with Cardiac Safety Monitoring content ---
        has_heading, has_content, heading_style_ok = _check_new_section_94(doc)
        if has_heading and has_content:
            score += POINTS
            detail = f"(heading style correct: {heading_style_ok})"
            feedback_parts.append(
                f"Section 9.4: 'Cardiac Safety Monitoring Plan' heading and 12-lead ECG content added {detail}"
            )
        elif has_heading:
            score += POINTS // 2
            feedback_parts.append(
                "Section 9.4: heading found but content about 12-lead ECG assessment is missing"
            )
        elif has_content:
            score += POINTS // 2
            feedback_parts.append(
                "Section 9.4: ECG content found but '9.4 Cardiac Safety Monitoring Plan' heading missing"
            )
        else:
            feedback_parts.append(
                "Section 9.4: NOT added — must create new subsection '9.4 Cardiac Safety Monitoring Plan' "
                "with Heading 2 style after Section 9.3"
            )

        # --- Criterion 7: Version history table updated with Version 2.0 row ---
        has_v2_row, has_amendment_desc, table_rows = _check_version_history_table(doc)
        if has_v2_row and has_amendment_desc:
            score += POINTS
            feedback_parts.append(
                f"Version history: table row for Version 2.0 with amendment description added "
                f"({table_rows} total rows)"
            )
        elif has_v2_row:
            score += POINTS // 2
            feedback_parts.append(
                "Version history: Version 2.0 row added but lacks amendment description "
                "(needs Protocol Amendment 1 details)"
            )
        else:
            feedback_parts.append(
                f"Version history: table not updated with Version 2.0 row "
                f"(Appendix A currently has {table_rows} rows)"
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
