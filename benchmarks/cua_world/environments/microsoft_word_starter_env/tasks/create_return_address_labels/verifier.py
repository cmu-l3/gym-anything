#!/usr/bin/env python3
"""
Verifier for create_return_address_labels task.

Verifies:
1. File creation: ShippingLabels.docx exists and was created/modified during the task.
2. Structure: Validates the document contains a table with ~30 cells (Avery 5160 layout).
3. Content: Checks for the company name and address.
4. Formatting: Checks for Bold on company name, Arial font, and Center alignment.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
import re
from xml.etree import ElementTree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_return_address_labels(traj, env_info, task_info):
    """
    Verify the return address labels task.
    """
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Metadata & Config
    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'ShippingLabels.docx')
    expected_path = metadata.get('expected_path', r"C:\Users\Docker\Documents\ShippingLabels.docx")
    
    # 3. Retrieve Result JSON and Document
    temp_dir = tempfile.mkdtemp()
    try:
        # Get result JSON
        local_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env(r"C:\Users\Docker\task_result.json", local_json_path)
            with open(local_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Get Document
        local_doc_path = os.path.join(temp_dir, expected_filename)
        doc_retrieved = False
        if result_data.get('output_exists'):
            try:
                copy_from_env(expected_path, local_doc_path)
                doc_retrieved = True
            except Exception as e:
                logger.error(f"Failed to copy document: {e}")

        # 4. Verify Logic
        score = 0
        feedback = []
        passed = False
        
        # Criterion 1: File Existence & Anti-Gaming (20 pts)
        if not doc_retrieved:
            feedback.append(f"FAIL: File {expected_filename} not found.")
            return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
        
        if not result_data.get('file_created_during_task'):
            feedback.append("FAIL: File timestamps indicate it was not modified during the task.")
            return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
        
        score += 20
        feedback.append("File created successfully.")

        # Parse the DOCX (XML)
        try:
            with zipfile.ZipFile(local_doc_path, 'r') as zf:
                xml_content = zf.read('word/document.xml')
                
                # Namespaces
                ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
                tree = ElementTree.fromstring(xml_content)

                # Criterion 2: Label Layout / Table Structure (30 pts)
                # Avery 5160 creates a table. We expect 30 cells (3 cols * 10 rows).
                # Note: Word sometimes adds empty paragraphs or weird structures, but the main table should be prominent.
                tables = tree.findall('.//w:tbl', ns)
                if not tables:
                    feedback.append("FAIL: No table found. Labels must be generated as a table.")
                else:
                    # Check the first table (usually the only one for labels)
                    cells = tables[0].findall('.//w:tc', ns)
                    cell_count = len(cells)
                    
                    # Avery 5160 is 3x10 = 30. Allow slight variation if they added a header row manually (unlikely for labels)
                    # or if Word splits things weirdly, but 30 is the standard target.
                    if 29 <= cell_count <= 31:
                        score += 30
                        feedback.append("Layout correct (Avery 5160 structure detected).")
                    elif cell_count > 0:
                        score += 10
                        feedback.append(f"Table found but cell count ({cell_count}) does not match Avery 5160 (30).")
                    else:
                        feedback.append("Table found but it is empty.")

                # Criterion 3: Content Accuracy (20 pts)
                # Extract all text
                paragraphs = tree.findall('.//w:p', ns)
                full_text = ""
                for p in paragraphs:
                    texts = p.findall('.//w:t', ns)
                    for t in texts:
                        if t.text:
                            full_text += t.text + " "
                
                content_score = 0
                if "Summit Peak Adventures" in full_text:
                    content_score += 10
                if "1400 Mountain View" in full_text:
                    content_score += 5
                if "Denver" in full_text and "80202" in full_text:
                    content_score += 5
                
                score += content_score
                if content_score == 20:
                    feedback.append("Address content correct.")
                else:
                    feedback.append(f"Partial address content found (Score: {content_score}/20).")

                # Criterion 4: Formatting (30 pts)
                # We need to find the specific runs for formatting checks.
                
                # Check for Bold on "Summit Peak Adventures" (10 pts)
                bold_found = False
                for p in paragraphs:
                    # Check if paragraph contains the company name
                    p_text = "".join([t.text for t in p.findall('.//w:t', ns) if t.text])
                    if "Summit" in p_text:
                        # Look for bold property in runs
                        runs = p.findall('.//w:r', ns)
                        for r in runs:
                            r_text = "".join([t.text for t in r.findall('.//w:t', ns) if t.text])
                            if "Summit" in r_text or "Adventures" in r_text:
                                rPr = r.find('w:rPr', ns)
                                if rPr is not None:
                                    # <w:b/> or <w:b w:val="true"/> or <w:b w:val="1"/>
                                    bold = rPr.find('w:b', ns)
                                    if bold is not None:
                                        val = bold.get(f'{{{ns["w"]}}}val')
                                        if val is None or val in ['true', '1', 'on']:
                                            bold_found = True
                                            break
                if bold_found:
                    score += 10
                    feedback.append("Company name is Bold.")
                else:
                    feedback.append("Company name is NOT Bold.")

                # Check for Arial Font (10 pts)
                # This can be set in styles or direct formatting.
                # We'll check direct formatting in runs as that's typical for this task.
                arial_found = False
                font_checks = tree.findall('.//w:rFonts', ns)
                for f in font_checks:
                    ascii_font = f.get(f'{{{ns["w"]}}}ascii')
                    h_ansi_font = f.get(f'{{{ns["w"]}}}hAnsi')
                    if (ascii_font and "Arial" in ascii_font) or (h_ansi_font and "Arial" in h_ansi_font):
                        arial_found = True
                        break
                
                if arial_found:
                    score += 10
                    feedback.append("Arial font detected.")
                else:
                    feedback.append("Arial font NOT detected (check if applied to text).")

                # Check for Center Alignment (10 pts)
                # Look for <w:jc w:val="center"/> in paragraph properties
                center_found = False
                # We check paragraphs that actually have text
                aligned_paras = 0
                total_text_paras = 0
                
                for p in paragraphs:
                    p_text = "".join([t.text for t in p.findall('.//w:t', ns) if t.text])
                    if len(p_text.strip()) > 0:
                        total_text_paras += 1
                        pPr = p.find('w:pPr', ns)
                        if pPr is not None:
                            jc = pPr.find('w:jc', ns)
                            if jc is not None:
                                val = jc.get(f'{{{ns["w"]}}}val')
                                if val == 'center':
                                    aligned_paras += 1
                
                # If majority of text paragraphs are centered, give credit
                if total_text_paras > 0 and (aligned_paras / total_text_paras) > 0.5:
                    score += 10
                    feedback.append("Text alignment is Center.")
                else:
                    feedback.append(f"Text alignment not consistently Center ({aligned_paras}/{total_text_paras} paragraphs).")

        except Exception as e:
            feedback.append(f"Error parsing document structure: {e}")
            score = 0

        # Final Evaluation
        if score >= 70:
            passed = True
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System error: {e}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)