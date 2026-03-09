#!/usr/bin/env python3
"""
Verifier for syllabus_accessibility_remediation task.
"""

import sys
import os
import logging
import json
import zipfile
import re
from xml.etree import ElementTree

# Import utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    check_heading_styles,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_docx_metadata_and_xml(docx_path):
    """
    Manually parse DOCX XML to check things python-docx misses:
    - Alt Text (descr attribute in wp:docPr)
    - Table Header (tblHeader in trPr)
    - Core Properties (Title)
    """
    results = {
        "title_metadata": None,
        "alt_texts": [],
        "table_header_rows": 0
    }
    
    try:
        with zipfile.ZipFile(docx_path, 'r') as z:
            # 1. Check Core Properties (Title)
            try:
                core_xml = z.read('docProps/core.xml')
                root = ElementTree.fromstring(core_xml)
                # Namespaces
                ns = {'dc': 'http://purl.org/dc/elements/1.1/'}
                title_elem = root.find('.//dc:title', ns)
                if title_elem is not None:
                    results["title_metadata"] = title_elem.text
            except Exception as e:
                logger.warning(f"Metadata parse error: {e}")

            # 2. Check Document Content for Alt Text and Table Headers
            try:
                doc_xml = z.read('word/document.xml')
                root = ElementTree.fromstring(doc_xml)
                
                # Namespaces usually used in DOCX
                namespaces = {
                    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
                    'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
                }

                # Find Alt Text in inline shapes
                # Look for <wp:docPr ... descr="Alt Text" ...>
                for docPr in root.findall('.//wp:docPr', namespaces):
                    descr = docPr.get('descr')
                    if descr:
                        results["alt_texts"].append(descr)

                # Find Table Headers
                # Look for rows <w:tr> containing <w:trPr><w:tblHeader/></w:trPr>
                for tr in root.findall('.//w:tr', namespaces):
                    trPr = tr.find('w:trPr', namespaces)
                    if trPr is not None:
                        tblHeader = trPr.find('w:tblHeader', namespaces)
                        if tblHeader is not None:
                            results["table_header_rows"] += 1
                            
            except Exception as e:
                logger.warning(f"Content parse error: {e}")

    except Exception as e:
        logger.error(f"Zip parse error: {e}")
        return None
        
    return results

def verify_syllabus_accessibility(traj, env_info, task_info):
    """
    Verify accessibility remediation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/CS101_Syllabus_Accessible.docx')
    
    # 1. Check File Existence & Basic Parse
    success, doc, error, temp_dir = copy_and_parse_document(
        output_path, copy_from_env, file_format='docx'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found or invalid: {error}",
            "details": {"error": error}
        }

    # Parse low-level XML for Alt Text and Metadata
    # We need the path to the temp file created by copy_and_parse_document
    # Since copy_and_parse returns a doc object, we need to reconstruct where the file is
    # Helper: copy_and_parse downloads to a temp dir. We can just re-download or rely on 
    # the fact we need the file path.
    # Actually, `copy_and_parse_document` implementation in utils downloads to `temp_dir/result.docx`.
    # Let's assume standard name based on util code:
    host_file_path = os.path.join(temp_dir, "result.docx")
    
    xml_data = parse_docx_metadata_and_xml(host_file_path) or {}
    
    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence (10 pts) ---
    score += 10
    feedback.append("File created successfully")

    # --- Criterion 2: Heading Styles (35 pts) ---
    # Heading 1
    h1_expected = {metadata.get('expected_title', "CS101"): "Heading 1"}
    h1_match, _, _ = check_heading_styles(doc, h1_expected)
    if h1_match == 1:
        score += 15
        feedback.append("Main Title set to Heading 1")
    else:
        feedback.append("Main Title NOT set to Heading 1")

    # Heading 2
    h2_sections = metadata.get('expected_sections', [])
    h2_expected = {sec: "Heading 2" for sec in h2_sections}
    h2_match, h2_total, _ = check_heading_styles(doc, h2_expected)
    
    # Proportional score for sections (max 20)
    if h2_total > 0:
        section_score = (h2_match / h2_total) * 20
        score += section_score
        feedback.append(f"Section headings: {h2_match}/{h2_total} correct")
    
    # --- Criterion 3: Alt Text (30 pts) ---
    alt_texts = xml_data.get('alt_texts', [])
    logo_alt = metadata.get('logo_alt_text', "")
    chart_alt = metadata.get('chart_alt_text', "")
    
    # Check Logo Alt Text (15 pts)
    logo_found = any(logo_alt.lower() in t.lower() for t in alt_texts)
    if logo_found:
        score += 15
        feedback.append("Logo Alt Text found")
    else:
        feedback.append("Logo Alt Text missing or incorrect")

    # Check Chart Alt Text (15 pts)
    # Allow partial match for long chart description
    chart_found = any("exams 40%" in t.lower() and "labs 30%" in t.lower() for t in alt_texts)
    if chart_found:
        score += 15
        feedback.append("Chart Alt Text found")
    else:
        feedback.append("Chart Alt Text missing or incorrect")

    # --- Criterion 4: Table Header (15 pts) ---
    header_rows = xml_data.get('table_header_rows', 0)
    if header_rows >= 1:
        score += 15
        feedback.append("Table Header Row configured")
    else:
        feedback.append("Table Header Row NOT configured")

    # --- Criterion 5: Metadata Title (10 pts) ---
    actual_title = xml_data.get('title_metadata', "")
    expected_meta = metadata.get('meta_title', "")
    if actual_title and expected_meta.lower() in actual_title.lower():
        score += 10
        feedback.append("Document Title metadata set")
    else:
        feedback.append(f"Document Title metadata missing (Got: '{actual_title}')")

    # Cleanup
    cleanup_verification_temp(temp_dir)

    return {
        "passed": score >= 70,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }