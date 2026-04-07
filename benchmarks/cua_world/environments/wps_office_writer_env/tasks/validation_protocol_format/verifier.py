#!/usr/bin/env python3
"""Verifier for validation_protocol_format task."""

import sys
import os
import re
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    get_table_content,
    count_headings_by_level
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_validation_protocol_format(traj, env_info, task_info):
    """
    Verify the IQ protocol formatting task based on GMP standards.
    
    CRITERIA (100 pts total):
    1. Heading 1 styles (10 main sections) - 15 pts
    2. Heading 2 styles (6 sub-sections) - 10 pts
    3. Equipment Identification table - 10 pts
    4. Test case tables (6 required) - 20 pts
    5. Acceptance criteria summary table - 10 pts
    6. Signature block present - 10 pts
    7. Body font (Times New Roman 12pt) - 10 pts
    8. Table header bold formatting - 5 pts
    9. Title formatting (centered, bold, >=16pt) - 5 pts
    10. Document created correctly during task time - 5 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata JSON to check anti-gaming timestamps
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/validation_protocol_format_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_meta.get("document_exists", False):
        return {"passed": False, "score": 0, "feedback": "Formatted document was not saved to the correct path."}

    # Retrieve and parse DOCX
    container_path = "/tmp/iq_protocol_formatted.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    score = 0
    feedback_parts = []
    
    # Check Anti-Gaming
    if result_meta.get("file_created_during_task", False):
        score += 5
        feedback_parts.append("File created during task (+5)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during task")

    try:
        full_text = get_document_text(doc).lower()
        xml_str = doc.element.xml

        # Prerequisite: Check data wasn't just deleted
        if "agilent 1260 infinity" not in full_text or "iq-006" not in full_text:
            return {"passed": False, "score": 0, "feedback": "Core content from original document was deleted or heavily corrupted."}

        # 1. Heading 1 check (Target: 10 sections)
        heading_counts = count_headings_by_level(doc)
        h1_count = heading_counts.get('Heading 1', 0)
        
        # In case the agent used custom styles, we look for paragraphs starting with "1.0", "2.0", etc.
        # and see if they are styled as headings or structurally act as headings.
        main_sections = ["1.0", "2.0", "3.0", "4.0", "5.0", "6.0", "7.0", "8.0", "9.0", "10.0"]
        h1_verified = 0
        for para in doc.paragraphs:
            if para.style and 'heading' in para.style.name.lower():
                for sec in main_sections:
                    if para.text.strip().startswith(sec):
                        h1_verified += 1
                        
        if h1_count >= 8 or h1_verified >= 8:
            score += 15
            feedback_parts.append(f"Heading 1 styles applied ({max(h1_count, h1_verified)}/10) (+15)")
        elif h1_count >= 4 or h1_verified >= 4:
            score += 7
            feedback_parts.append(f"Heading 1 styles partial ({max(h1_count, h1_verified)}/10) (+7)")
        else:
            feedback_parts.append("Heading 1 styles missing or insufficient")

        # 2. Heading 2 check (Target: 6 test cases)
        h2_count = heading_counts.get('Heading 2', 0)
        h2_verified = 0
        sub_sections = ["7.1", "7.2", "7.3", "7.4", "7.5", "7.6"]
        for para in doc.paragraphs:
            if para.style and 'heading' in para.style.name.lower():
                for sec in sub_sections:
                    if para.text.strip().startswith(sec):
                        h2_verified += 1

        if h2_count >= 4 or h2_verified >= 4:
            score += 10
            feedback_parts.append(f"Heading 2 styles applied ({max(h2_count, h2_verified)}/6) (+10)")
        elif h2_count >= 2 or h2_verified >= 2:
            score += 5
            feedback_parts.append("Heading 2 styles partial (+5)")
        else:
            feedback_parts.append("Heading 2 styles missing")

        # Table processing
        num_tables = count_tables(doc)
        equipment_table_found = False
        test_tables_found = 0
        summary_table_found = False
        bold_headers = 0

        for t_idx in range(num_tables):
            content = get_table_content(doc, t_idx)
            if not content:
                continue
            
            flat_content = " ".join([" ".join(row).lower() for row in content])
            
            # Check Equipment Table
            if "manufacturer" in flat_content and "agilent" in flat_content and "model" in flat_content:
                equipment_table_found = True
                
            # Check Test Case Tables
            if "expected result" in flat_content and "actual result" in flat_content and "iq-00" in flat_content:
                test_tables_found += 1
                
            # Check Summary Table
            if "test id" in flat_content and "status" in flat_content and "iq-001" in flat_content and "iq-002" in flat_content:
                summary_table_found = True

            # Check bold headers (inspecting the XML of the first row or python-docx run properties)
            try:
                first_row = doc.tables[t_idx].rows[0]
                is_bold = False
                for cell in first_row.cells:
                    for para in cell.paragraphs:
                        for run in para.runs:
                            if run.bold:
                                is_bold = True
                                break
                if is_bold:
                    bold_headers += 1
            except:
                pass

        # 3. Equipment Table
        if equipment_table_found:
            score += 10
            feedback_parts.append("Equipment table created (+10)")
        else:
            feedback_parts.append("Equipment table missing")

        # 4. Test Case Tables
        if test_tables_found >= 5:
            score += 20
            feedback_parts.append(f"Test case tables created ({test_tables_found}/6) (+20)")
        elif test_tables_found >= 3:
            score += 10
            feedback_parts.append(f"Test case tables partial ({test_tables_found}/6) (+10)")
        else:
            feedback_parts.append(f"Test case tables missing or insufficient ({test_tables_found}/6)")

        # 5. Summary Table
        if summary_table_found:
            score += 10
            feedback_parts.append("Summary table created (+10)")
        else:
            feedback_parts.append("Summary table missing")

        # 6. Signature Block
        if "prepared by" in full_text and "reviewed by" in full_text and "approved by" in full_text:
            score += 10
            feedback_parts.append("Signature block present (+10)")
        else:
            feedback_parts.append("Signature block missing")

        # 7. Body Font (Times New Roman 12pt)
        # We'll check the document XML for widespread usage of Times New Roman and size 24 (12pt)
        font_score = 0
        if "Times New Roman" in xml_str:
            font_score += 5
        if 'w:sz w:val="24"' in xml_str:
            font_score += 5
            
        if font_score == 10:
            score += 10
            feedback_parts.append("Body font correctly set (+10)")
        elif font_score == 5:
            score += 5
            feedback_parts.append("Body font partially correct (+5)")
        else:
            feedback_parts.append("Body font formatting missing")

        # 8. Table Headers Bold
        if num_tables > 0 and bold_headers >= (num_tables / 2):
            score += 5
            feedback_parts.append("Table headers bolded (+5)")
        else:
            feedback_parts.append("Table headers not bolded")

        # 9. Title Formatting
        title_ok = False
        for para in doc.paragraphs[:5]:
            if "INSTALLATION QUALIFICATION" in para.text.upper():
                align = str(para.alignment)
                if align == "CENTER" or para.alignment == 1:
                    for run in para.runs:
                        if run.bold and run.font.size and run.font.size.pt >= 15: # Allow slight rounding
                            title_ok = True
                            break
        
        # Fallback check via XML for center and bold
        if not title_ok and "INSTALLATION QUALIFICATION" in xml_str and 'w:jc w:val="center"' in xml_str and 'w:b/' in xml_str:
            title_ok = True

        if title_ok:
            score += 5
            feedback_parts.append("Title formatted correctly (+5)")
        else:
            feedback_parts.append("Title not correctly formatted")

        # VLM trajectory verification is normally injected by framework (omitted here as requested logic is programmatic)
        # Passing requires at least 60 points and 4 test tables generated + 6 heading 1s.
        key_criteria = (test_tables_found >= 4) and (h1_count >= 6 or h1_verified >= 6)
        passed = (score >= 60) and key_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {str(e)}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {str(e)}"}