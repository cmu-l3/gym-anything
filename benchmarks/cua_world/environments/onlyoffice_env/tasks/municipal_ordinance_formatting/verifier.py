#!/usr/bin/env python3
"""
Verifier for Municipal Ordinance Formatting task.

Verifies the output document using programmatically parsed features:
1. File Existence & Timestamps (Anti-Gaming)
2. Paragraph alignments (Center, Right)
3. Typographical changes (Bold, 14pt/18pt)
4. Structural additions (Converting raw text to table)
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    check_text_formatting,
    check_paragraph_alignment,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_municipal_ordinance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # 1. Load exported metrics
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/municipal_ordinance_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Basic file validations (Anti-Gaming)
    if not result.get("output_file_exists", False):
        return {"passed": False, "score": 0.0, "feedback": "Target document str_ordinance_final.docx not found."}

    if not result.get("file_modified_during_task", False):
        return {"passed": False, "score": 0.0, "feedback": "File exists but was not created/modified during the task session."}

    # 3. Parse the document directly
    container_path = "/home/ga/Documents/TextDocuments/str_ordinance_final.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_ordinance_')
    
    try:
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        if not success:
            return {"passed": False, "score": 10.0, "feedback": f"File exists but failed to parse: {error}"}

        score = 10.0
        feedback = ["File output successfully parsed (10/100)"]

        # 4. Title Formatting (25 points): Center Aligned, Bold, 18pt
        title_aligned = check_paragraph_alignment(doc, "ORDINANCE NO.", "center") or check_paragraph_alignment(doc, "ORDINANCE", "center")
        title_fmt = check_text_formatting(doc, "ORDINANCE", bold=True, font_size=18.0)
        
        if title_aligned and title_fmt:
            score += 25.0
            feedback.append("Title properly formatted and centered (25/25)")
        elif title_aligned:
            score += 10.0
            feedback.append("Title center-aligned but font size/bold incorrect (10/25)")
        elif title_fmt:
            score += 15.0
            feedback.append("Title font size/bold correct but not center-aligned (15/25)")
        else:
            feedback.append("Title not correctly formatted (0/25)")

        # 5. Header Formatting (20 points): Bold, 14pt
        metadata = task_info.get('metadata', {})
        header_texts = metadata.get('expected_headers', ["Section 1", "Section 2", "Section 3", "Section 4"])
        headers_correct = 0
        
        for h in header_texts:
            if check_text_formatting(doc, h, bold=True, font_size=14.0):
                headers_correct += 1

        if headers_correct == len(header_texts):
            score += 20.0
            feedback.append("All headers properly formatted with 14pt/Bold (20/20)")
        elif headers_correct > 0:
            pts = headers_correct * 5.0
            score += pts
            feedback.append(f"{headers_correct}/4 headers properly formatted ({pts}/20)")
        else:
            feedback.append("Headers not properly formatted (0/20)")

        # 6. Penalty Table (25 points): Validate structural conversion to a Table
        num_tables = count_tables(doc)
        table_has_content = False
        if num_tables > 0:
            for table in doc.tables:
                table_text = " ".join([cell.text for row in table.rows for cell in row.cells]).lower()
                # Ensure the text from the raw penalty block is inside the table cells
                if "tier 1" in table_text and "250" in table_text and "revocation" in table_text:
                    table_has_content = True
                    break
        
        if num_tables > 0 and table_has_content:
            score += 25.0
            feedback.append("Penalty table successfully created and populated (25/25)")
        elif num_tables > 0:
            score += 10.0
            feedback.append("Table created but missing expected penalty data (10/25)")
        else:
            feedback.append("No table found in document (0/25)")

        # 7. Signature Alignment (20 points): Right Aligned
        sig_aligned_mayor = check_paragraph_alignment(doc, "Jane Doe", "right")
        sig_aligned_clerk = check_paragraph_alignment(doc, "John Smith", "right")
        
        if sig_aligned_mayor and sig_aligned_clerk:
            score += 20.0
            feedback.append("Signature block properly right-aligned (20/20)")
        elif sig_aligned_mayor or sig_aligned_clerk:
            score += 10.0
            feedback.append("Signature block partially right-aligned (10/20)")
        else:
            feedback.append("Signature block not right-aligned (0/20)")

        # Evaluate pass threshold
        passed = score >= 70.0 and num_tables > 0
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0.0, "feedback": f"Verification execution error: {e}"}
    finally:
        cleanup_temp_dir(temp_dir)