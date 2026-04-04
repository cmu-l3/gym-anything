#!/usr/bin/env python3
"""Verifier for business_impact_analysis task."""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    count_tables,
    get_table_dimensions,
    get_table_content,
    check_heading_styles,
    count_headings_by_level,
    check_table_header_formatting,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_business_impact_analysis(traj, env_info, task_info):
    """
    Verify that the BIA document was properly structured from interview notes.

    PREREQUISITE: Core interview content must be preserved.

    SCORING CRITERIA:
    1. Document structure: BIA sections with heading styles
    2. Heading hierarchy: Multiple heading levels used
    3. Recovery Priority table: Contains RTO/RPO data for processes
    4. Risk Assessment Matrix: 5x5 or similar likelihood-impact grid
    5. RACI matrix: Responsibility assignment table
    6. Table formatting: At least one table has formatted headers
    7. Executive summary: Summary section present at start
    8. Process data completeness: All 6 processes referenced
    9. VLM visual verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/bia_notes.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        feedback_parts = []
        full_text = get_document_text(doc).lower()

        # PREREQUISITE: Interview content must be preserved
        key_phrases = [
            "pinnacle financial",
            "core banking",
            "payment processing",
            "recovery time",
            "ransomware",
        ]
        preserved = sum(1 for p in key_phrases if p.lower() in full_text)
        if preserved < 3:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"PREREQUISITE FAILED: Content corrupted ({preserved}/{len(key_phrases)} key phrases)",
            }
        feedback_parts.append(f"Prerequisite: content preserved ({preserved}/{len(key_phrases)})")

        criteria_passed = 0
        total_criteria = 9

        # Criterion 1: BIA sections with heading styles
        bia_sections = {
            "executive summary": "Heading",
            "risk assessment": "Heading",
            "recovery": "Heading",
            "recommendation": "Heading",
        }
        sections_found = 0
        for section_text, _ in bia_sections.items():
            for para in doc.paragraphs:
                if section_text in para.text.lower():
                    if para.style and 'heading' in para.style.name.lower():
                        sections_found += 1
                    break

        if sections_found >= 3:
            criteria_passed += 1
            feedback_parts.append(f"BIA sections: {sections_found}/{len(bia_sections)} have heading styles")
        else:
            feedback_parts.append(f"BIA sections: only {sections_found}/{len(bia_sections)} have heading styles")

        # Criterion 2: Heading hierarchy - multiple levels
        heading_counts = count_headings_by_level(doc)
        levels_used = len(heading_counts)
        total_headings = sum(heading_counts.values())

        if levels_used >= 2 and total_headings >= 5:
            criteria_passed += 1
            feedback_parts.append(f"Heading hierarchy: {levels_used} levels, {total_headings} headings")
        else:
            feedback_parts.append(f"Heading hierarchy: {levels_used} levels, {total_headings} headings (need 2+ levels, 5+ headings)")

        # Criterion 3: Recovery Priority table with RTO/RPO data
        table_count = count_tables(doc)
        recovery_table_found = False
        for t_idx in range(table_count):
            content = get_table_content(doc, t_idx)
            if not content:
                continue
            all_text = ' '.join(' '.join(row) for row in content).lower()
            # Recovery table should have process names + RTO/RPO values
            has_rto = 'rto' in all_text or 'recovery time' in all_text
            has_processes = sum(1 for p in ['core banking', 'payment', 'customer portal', 'risk analytics']
                              if p in all_text)
            if has_rto and has_processes >= 2:
                recovery_table_found = True
                rows, cols = get_table_dimensions(doc, t_idx)
                feedback_parts.append(f"Recovery table: found ({rows}x{cols}, {has_processes} processes)")
                break

        if recovery_table_found:
            criteria_passed += 1
        else:
            feedback_parts.append("Recovery table: NOT found (need RTO/RPO + process names)")

        # Criterion 4: Risk Assessment Matrix (likelihood x impact grid)
        risk_matrix_found = False
        for t_idx in range(table_count):
            content = get_table_content(doc, t_idx)
            if not content:
                continue
            all_text = ' '.join(' '.join(row) for row in content).lower()
            rows, cols = get_table_dimensions(doc, t_idx)
            # Risk matrix should be grid-like (>=4x4) with likelihood/impact terms
            has_risk_terms = any(term in all_text for term in
                               ['likelihood', 'probability', 'impact', 'severity', 'critical', 'high', 'medium', 'low'])
            if rows >= 4 and cols >= 4 and has_risk_terms:
                risk_matrix_found = True
                feedback_parts.append(f"Risk matrix: found ({rows}x{cols})")
                break
            # Also accept smaller matrices with clear risk terminology
            if rows >= 3 and cols >= 3 and sum(1 for t in ['high', 'medium', 'low', 'critical'] if t in all_text) >= 3:
                risk_matrix_found = True
                feedback_parts.append(f"Risk matrix: found ({rows}x{cols})")
                break

        if risk_matrix_found:
            criteria_passed += 1
        else:
            feedback_parts.append("Risk matrix: NOT found (need likelihood x impact grid)")

        # Criterion 5: RACI matrix
        raci_found = False
        for t_idx in range(table_count):
            content = get_table_content(doc, t_idx)
            if not content:
                continue
            all_text = ' '.join(' '.join(row) for row in content).lower()
            # RACI should contain R, A, C, I letters and role/process references
            has_raci = 'raci' in full_text or (
                sum(1 for letter in ['r', 'a', 'c', 'i']
                    if any(cell.strip().upper() in ['R', 'A', 'C', 'I', 'R/A', 'A/R']
                           for row in content for cell in row)) >= 3
            )
            has_roles = any(term in all_text for term in
                          ['it operations', 'compliance', 'digital', 'crisis', 'tom', 'lisa', 'david', 'amy'])
            if has_raci or (has_roles and len(content) >= 4):
                raci_found = True
                rows, cols = get_table_dimensions(doc, t_idx)
                feedback_parts.append(f"RACI matrix: found ({rows}x{cols})")
                break

        if raci_found:
            criteria_passed += 1
        else:
            feedback_parts.append("RACI matrix: NOT found")

        # Criterion 6: Table formatting - at least one table has formatted headers
        any_formatted = False
        for t_idx in range(table_count):
            header_fmt = check_table_header_formatting(doc, t_idx)
            if header_fmt['has_bold'] or header_fmt['has_shading']:
                any_formatted = True
                break

        if any_formatted:
            criteria_passed += 1
            feedback_parts.append("Table formatting: at least one table has formatted headers")
        else:
            feedback_parts.append("Table formatting: no tables have formatted headers")

        # Criterion 7: Executive summary present
        exec_summary_found = False
        for i, para in enumerate(doc.paragraphs):
            if 'executive summary' in para.text.lower() or 'summary' in para.text.lower():
                # Check it's near the beginning (first 20% of paragraphs)
                if i < len(doc.paragraphs) * 0.3:
                    exec_summary_found = True
                    break

        if exec_summary_found:
            criteria_passed += 1
            feedback_parts.append("Executive summary: present near document start")
        else:
            feedback_parts.append("Executive summary: NOT found near start of document")

        # Criterion 8: Process data completeness - all 6 processes referenced
        processes = ['core banking', 'payment processing', 'customer portal',
                     'risk analytics', 'email', 'regulatory reporting']
        processes_found = sum(1 for p in processes if p in full_text)

        if processes_found >= 5:
            criteria_passed += 1
            feedback_parts.append(f"Process coverage: {processes_found}/{len(processes)} processes referenced")
        else:
            feedback_parts.append(f"Process coverage: only {processes_found}/{len(processes)}")

        # Criterion 9: VLM verification
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Writer screenshot of a business continuity document. Answer in JSON:
{
    "has_section_headings": true/false,
    "has_tables": true/false,
    "has_structured_layout": true/false,
    "appears_professionally_formatted": true/false
}
Does the document show:
1. Clear section headings?
2. Data tables (risk matrix, recovery priorities, or RACI)?
3. Structured document layout (not raw interview notes)?
4. Professional formatting throughout?
""")
        if vlm_result is not None:
            has_tables = vlm_result.get("has_tables", False)
            structured = vlm_result.get("has_structured_layout", False)
            if has_tables or structured:
                criteria_passed += 1
                feedback_parts.append("VLM: structured BIA format confirmed")
            else:
                feedback_parts.append("VLM: structured format not confirmed")
        else:
            total_criteria -= 1
            feedback_parts.append("VLM: unavailable (skipped)")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 55

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
