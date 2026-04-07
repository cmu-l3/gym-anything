#!/usr/bin/env python3

import os
import json
import tempfile
import logging
import zipfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_text_and_format_xml(docx_path):
    """
    Robust native OOXML parser that does not require python-docx.
    Analyzes content, alignment, bold tags, and font sizes.
    """
    result = {
        "success": True,
        "text_content": "",
        "title_found": False,
        "title_formatted": False,
        "headings_formatted": 0,
        "justified_paras": 0,
        "total_body_paras": 0,
        "tables_count": 0,
        "table_text": ""
    }
    
    try:
        with zipfile.ZipFile(docx_path, 'r') as z:
            xml_content = z.read('word/document.xml')
        
        root = ET.fromstring(xml_content)
        ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        
        # Count tables and extract table text
        tables = root.findall('.//w:tbl', ns)
        result["tables_count"] = len(tables)
        for tbl in tables:
            for t in tbl.findall('.//w:t', ns):
                if t.text: 
                    result["table_text"] += t.text.lower() + " "
                
        # Analyze paragraphs
        paras = root.findall('.//w:p', ns)
        headings_to_check = ["staff economic outlook", "participants' views on current conditions"]
        headings_found = set()
        
        for p in paras:
            texts = p.findall('.//w:t', ns)
            p_text = "".join([t.text for t in texts if t.text])
            if not p_text.strip():
                continue
            
            result["text_content"] += p_text.lower() + "\n"
            
            # Extract paragraph alignment properties
            pPr = p.find('.//w:pPr', ns)
            alignment = None
            if pPr is not None:
                jc = pPr.find('.//w:jc', ns)
                if jc is not None:
                    alignment = jc.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}val')
            
            # Extract run properties (bold, font size)
            runs = p.findall('.//w:r', ns)
            has_bold = False
            has_18pt = False  # 36 half-points
            has_14pt = False  # 28 half-points
            
            for r in runs:
                rPr = r.find('.//w:rPr', ns)
                if rPr is not None:
                    # Check Bold
                    b = rPr.find('.//w:b', ns)
                    if b is not None:
                        val = b.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}val')
                        if val not in ['0', 'false']:
                            has_bold = True
                    
                    # Check Font Size
                    sz = rPr.find('.//w:sz', ns)
                    szCs = rPr.find('.//w:szCs', ns)
                    for size_node in (sz, szCs):
                        if size_node is not None:
                            val = size_node.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}val')
                            if val == '36': 
                                has_18pt = True
                            if val == '28': 
                                has_14pt = True
            
            # Verify Title
            if "federal reserve fomc briefing" in p_text.lower():
                result["title_found"] = True
                if alignment == 'center' and has_bold and has_18pt:
                    result["title_formatted"] = True
                    
            # Verify Headings
            for h in headings_to_check:
                if h in p_text.lower() and h not in headings_found:
                    if has_bold and has_14pt:
                        result["headings_formatted"] += 1
                        headings_found.add(h)
                        
            # Verify Body Paragraphs (Assuming >50 chars qualifies as standard body)
            if len(p_text) > 50:
                result["total_body_paras"] += 1
                if alignment == 'both':  # 'both' is OOXML terminology for Justified
                    result["justified_paras"] += 1
                    
        return result
    except Exception as e:
        return {"success": False, "error": str(e)}


def verify_fomc_briefing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', "/home/ga/Documents/TextDocuments/FOMC_Client_Briefing.docx")
    
    # Pull export status JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get("output_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file FOMC_Client_Briefing.docx was not created.",
            "details": {"file_exists": False}
        }

    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming creation check (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created successfully during task")
    else:
        feedback_parts.append("File found, but creation timestamp violates task window")

    # Pull DOCX file for deep parsing
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env(expected_path, temp_docx.name)
        
        doc_data = extract_text_and_format_xml(temp_docx.name)
        if not doc_data.get("success"):
            return {
                "passed": False,
                "score": score,
                "feedback": f"Failed to parse OOXML document: {doc_data.get('error')}"
            }
            
        text_content = doc_data["text_content"]

        # 2. Text Integration check (15 pts)
        if "recent indicators suggest" in text_content and "unemployment rate" in text_content:
            score += 15
            feedback_parts.append("Core FOMC text successfully integrated")
        else:
            feedback_parts.append("Missing core text passages from source txt")

        # 3. Title Formatting check (20 pts)
        if doc_data["title_formatted"]:
            score += 20
            feedback_parts.append("Title correctly formatted (18pt, Bold, Centered)")
        elif doc_data["title_found"]:
            score += 10
            feedback_parts.append("Title found but formatting specifications unmet")
        else:
            feedback_parts.append("Required title 'Federal Reserve FOMC Briefing' missing")

        # 4. Heading Formatting check (15 pts)
        if doc_data["headings_formatted"] == 2:
            score += 15
            feedback_parts.append("Both section headings correctly formatted (14pt, Bold)")
        elif doc_data["headings_formatted"] == 1:
            score += 7
            feedback_parts.append("Partial heading formatting complete")
        else:
            feedback_parts.append("Section headings lack correct formatting")

        # 5. Body Alignment check (15 pts)
        total_body = doc_data["total_body_paras"]
        justified = doc_data["justified_paras"]
        
        if total_body > 0 and justified >= (total_body * 0.5):
            score += 15
            feedback_parts.append("Body paragraphs successfully Justified")
        else:
            feedback_parts.append("Body paragraphs are not predominantly Justified")

        # 6. Table & CSV Data Integration check (25 pts)
        if doc_data["tables_count"] >= 1:
            score += 10
            feedback_parts.append("Table structure detected")
            
            table_text = doc_data["table_text"]
            if "pce inflation" in table_text and "2.6" in table_text and "unemployment" in table_text:
                score += 15
                feedback_parts.append("Table correctly populated with CSV SEP data")
            else:
                feedback_parts.append("Table found but missing required CSV projection data")
        else:
            feedback_parts.append("No table structures found in document")

    finally:
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {"score": score}
    }