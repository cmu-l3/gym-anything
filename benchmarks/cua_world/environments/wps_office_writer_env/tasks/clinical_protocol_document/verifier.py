#!/usr/bin/env python3
"""Verifier for clinical_protocol_document task."""

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


def verify_clinical_protocol_document(traj, env_info, task_info):
    """
    Verify that the clinical protocol was properly structured.

    PREREQUISITE: Clinical content must be preserved.

    SCORING CRITERIA:
    1. Heading styles: Protocol sections have heading styles
    2. Heading hierarchy: Multiple levels used
    3. Dosing table: Renal adjustment data in tabular format
    4. Adverse reactions table: Organized by frequency/severity
    5. Monitoring schedule table: Lab tests and frequency
    6. Missing sections added: Purpose, Scope, Equipment, Revision History
    7. Table formatting: Professional header formatting
    8. Content preservation: Critical clinical data intact
    9. VLM visual verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/vanc_protocol_draft.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        feedback_parts = []
        full_text = get_document_text(doc).lower()

        # PREREQUISITE: Clinical content must be preserved
        key_phrases = [
            "vancomycin",
            "mrsa",
            "nephrotoxicity",
            "red man syndrome",
            "auc/mic",
            "serum creatinine",
        ]
        preserved = sum(1 for p in key_phrases if p.lower() in full_text)
        if preserved < 4:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"PREREQUISITE FAILED: Clinical content corrupted ({preserved}/{len(key_phrases)} key phrases)",
            }
        feedback_parts.append(f"Prerequisite: clinical content preserved ({preserved}/{len(key_phrases)})")

        criteria_passed = 0
        total_criteria = 9

        # Criterion 1: Protocol sections have heading styles
        protocol_sections = {
            "dosing": "Heading",
            "monitoring": "Heading",
            "adverse": "Heading",
            "contraindication": "Heading",
            "administration": "Heading",
            "indication": "Heading",
            "references": "Heading",
        }
        sections_styled = 0
        for section_text, _ in protocol_sections.items():
            for para in doc.paragraphs:
                if section_text in para.text.lower():
                    if para.style and 'heading' in para.style.name.lower():
                        sections_styled += 1
                    break

        if sections_styled >= 5:
            criteria_passed += 1
            feedback_parts.append(f"Section headings: {sections_styled}/{len(protocol_sections)} styled")
        else:
            feedback_parts.append(f"Section headings: only {sections_styled}/{len(protocol_sections)} (need 5+)")

        # Criterion 2: Heading hierarchy - multiple levels
        heading_counts = count_headings_by_level(doc)
        levels_used = len(heading_counts)
        total_headings = sum(heading_counts.values())

        if levels_used >= 2 and total_headings >= 6:
            criteria_passed += 1
            feedback_parts.append(f"Heading hierarchy: {levels_used} levels, {total_headings} headings")
        elif total_headings >= 6:
            feedback_parts.append(f"Heading hierarchy: {total_headings} headings but only {levels_used} level")
        else:
            feedback_parts.append(f"Heading hierarchy: insufficient ({total_headings} headings)")

        # Criterion 3: Dosing table with renal adjustment data
        table_count = count_tables(doc)
        dosing_table_found = False
        for t_idx in range(table_count):
            content = get_table_content(doc, t_idx)
            if not content:
                continue
            all_text = ' '.join(' '.join(row) for row in content).lower()
            has_dosing = any(term in all_text for term in
                           ['mg/kg', 'dose', 'crcl', 'creatinine clearance', 'renal',
                            'every 8', 'every 12', 'every 24', 'loading'])
            if has_dosing:
                dosing_table_found = True
                rows, cols = get_table_dimensions(doc, t_idx)
                feedback_parts.append(f"Dosing table: found ({rows}x{cols})")
                break

        if dosing_table_found:
            criteria_passed += 1
        else:
            feedback_parts.append("Dosing table: NOT found (need renal adjustment data in table)")

        # Criterion 4: Adverse reactions table
        adverse_table_found = False
        for t_idx in range(table_count):
            content = get_table_content(doc, t_idx)
            if not content:
                continue
            all_text = ' '.join(' '.join(row) for row in content).lower()
            has_adverse = any(term in all_text for term in
                            ['red man', 'nephrotoxicity', 'phlebitis', 'ototoxicity',
                             'adverse', 'common', 'uncommon', 'frequency', 'severity'])
            if has_adverse:
                adverse_table_found = True
                rows, cols = get_table_dimensions(doc, t_idx)
                feedback_parts.append(f"Adverse reactions table: found ({rows}x{cols})")
                break

        if adverse_table_found:
            criteria_passed += 1
        else:
            feedback_parts.append("Adverse reactions table: NOT found")

        # Criterion 5: Monitoring schedule table
        monitoring_table_found = False
        for t_idx in range(table_count):
            content = get_table_content(doc, t_idx)
            if not content:
                continue
            all_text = ' '.join(' '.join(row) for row in content).lower()
            has_monitoring = any(term in all_text for term in
                               ['creatinine', 'trough', 'cbc', 'baseline',
                                'monitoring', 'frequency', 'lab', 'test', 'weekly', 'daily'])
            # Don't count the same table as both dosing and monitoring
            has_dosing_overlap = any(term in all_text for term in ['mg/kg', 'loading dose'])
            if has_monitoring and not has_dosing_overlap:
                monitoring_table_found = True
                rows, cols = get_table_dimensions(doc, t_idx)
                feedback_parts.append(f"Monitoring table: found ({rows}x{cols})")
                break

        if monitoring_table_found:
            criteria_passed += 1
        else:
            # Also accept if monitoring data is in the dosing table
            if table_count >= 3:
                criteria_passed += 1
                feedback_parts.append("Monitoring table: 3+ tables present (assumed monitoring included)")
            else:
                feedback_parts.append("Monitoring table: NOT found")

        # Criterion 6: Missing sections added
        missing_sections_added = 0
        missing_keywords = ['purpose', 'scope', 'equipment', 'revision history']
        for keyword in missing_keywords:
            if keyword in full_text:
                missing_sections_added += 1

        if missing_sections_added >= 3:
            criteria_passed += 1
            feedback_parts.append(f"Missing sections: {missing_sections_added}/4 added")
        else:
            feedback_parts.append(f"Missing sections: only {missing_sections_added}/4 added")

        # Criterion 7: Table formatting
        any_formatted = False
        for t_idx in range(min(table_count, 5)):
            header_fmt = check_table_header_formatting(doc, t_idx)
            if header_fmt['has_bold'] or header_fmt['has_shading']:
                any_formatted = True
                break

        if any_formatted:
            criteria_passed += 1
            feedback_parts.append("Table formatting: formatted headers present")
        else:
            feedback_parts.append("Table formatting: no formatted table headers")

        # Criterion 8: Content preservation - critical clinical data
        critical_data = [
            "25-30 mg/kg",           # Loading dose
            "15-20 mg/kg",           # Maintenance dose
            "400-600",               # AUC target
            "15-20 mcg/ml",          # Trough target
            "10 mg/min",             # Max infusion rate
        ]
        data_preserved = sum(1 for d in critical_data if d.lower() in full_text)
        if data_preserved >= 4:
            criteria_passed += 1
            feedback_parts.append(f"Clinical data: {data_preserved}/{len(critical_data)} values preserved")
        else:
            feedback_parts.append(f"Clinical data: only {data_preserved}/{len(critical_data)} preserved")

        # Criterion 9: VLM verification
        vlm_result = vlm_verify_screenshot(env_info, traj, """
Analyze this WPS Writer screenshot of a clinical protocol document. Answer in JSON:
{
    "has_section_headings": true/false,
    "has_tables": true/false,
    "appears_medical_document": true/false,
    "has_structured_layout": true/false
}
Does the document show:
1. Clear section headings for a clinical protocol?
2. Data tables (dosing, adverse reactions, or monitoring)?
3. Medical/clinical document appearance?
4. Structured layout with proper formatting?
""")
        if vlm_result is not None:
            has_tables = vlm_result.get("has_tables", False)
            is_medical = vlm_result.get("appears_medical_document", False)
            if has_tables or is_medical:
                criteria_passed += 1
                feedback_parts.append("VLM: clinical protocol format confirmed")
            else:
                feedback_parts.append("VLM: clinical format not confirmed")
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
