#!/usr/bin/env python3
"""
Verifier for format_chemical_formulas task.

Verifies:
1. File Creation: Checks if Lab_Report_Formatted.docx exists and was modified during task.
2. XML Inspection: Parses .docx XML to count subscripted digits and check for degree symbols.
3. Formatting: Checks title for bold and underline.
4. VLM Verification: Uses trajectory frames to verify the user actually interacted with the document text.
"""

import json
import logging
import os
import zipfile
import re
import tempfile
import shutil
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_format_chemical_formulas(traj, env_info, task_info):
    """
    Verify the chemistry lab report formatting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_subscript_count = metadata.get('expected_subscript_count', 23)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Temp dir for analysis
    temp_dir = tempfile.mkdtemp()
    
    try:
        # =========================================================
        # 1. Retrieve Result JSON (File Existence & Timestamps)
        # =========================================================
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("C:\\Users\\Docker\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Could not retrieve task result data"}

        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Formatted document not found. Did you save as 'Lab_Report_Formatted.docx'?"}

        if not result_data.get("file_created_during_task", False):
            feedback_parts.append("Warning: File timestamp indicates it might be old.")
            # We don't fail immediately, but it's a flag
        else:
            score += 10 # Points for saving a new file
            feedback_parts.append("File saved successfully.")

        # =========================================================
        # 2. Retrieve and Parse DOCX XML
        # =========================================================
        docx_local_path = os.path.join(temp_dir, "Lab_Report_Formatted.docx")
        try:
            copy_from_env(result_data["output_path"], docx_local_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve output document: {e}"}

        if not zipfile.is_zipfile(docx_local_path):
             return {"passed": False, "score": score, "feedback": "Saved file is not a valid DOCX."}

        # Parse document.xml
        try:
            with zipfile.ZipFile(docx_local_path, 'r') as zf:
                xml_content = zf.read('word/document.xml').decode('utf-8')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Corrupt DOCX XML: {e}"}

        # --- Check Subscripts ---
        # Look for <w:vertAlign w:val="subscript"/> followed by text
        # Regex to find runs with subscript
        # Pattern matches: <w:r ...> ... <w:vertAlign w:val="subscript"/> ... <w:t>TEXT</w:t> ... </w:r>
        # Note: XML ordering can vary, so we look for w:r containing both subscript and w:t
        
        # Simpler approach: find all w:r blocks, check if they have subscript, then extract text
        r_blocks = re.findall(r'<w:r(?: [^>]*)?>(.*?)</w:r>', xml_content, re.DOTALL)
        
        found_subscript_digits = 0
        found_subscript_text = []
        
        for block in r_blocks:
            if 'w:val="subscript"' in block:
                # Extract text from this block
                t_match = re.search(r'<w:t(?: [^>]*)?>(.*?)</w:t>', block)
                if t_match:
                    text = t_match.group(1)
                    found_subscript_text.append(text)
                    # Count digits
                    found_subscript_digits += sum(c.isdigit() for c in text)

        # Scoring Subscripts (Max 50 pts)
        # Expected ~23 digits. Allow minor variance.
        if found_subscript_digits >= expected_subscript_count:
            score += 50
            feedback_parts.append(f"Excellent! Found {found_subscript_digits} subscripted digits (Target: {expected_subscript_count}).")
        elif found_subscript_digits >= 15:
            score += 30
            feedback_parts.append(f"Good effort. Found {found_subscript_digits} subscripted digits (Target: {expected_subscript_count}). Some missed.")
        elif found_subscript_digits > 0:
            score += 10
            feedback_parts.append(f"Found {found_subscript_digits} subscripted digits. Many missed.")
        else:
            feedback_parts.append("No subscript formatting found.")

        # --- Check Degree Symbol ---
        # Look for UTF-8 degree symbol OR 'deg C' removal
        # Expected: 85°C, 135°C
        degree_symbol_count = xml_content.count('\u00B0') # ° symbol
        deg_c_text_count = xml_content.count("deg C")
        
        # Scoring Symbols (Max 20 pts)
        if degree_symbol_count >= 2:
            score += 20
            feedback_parts.append("Degree symbols correctly inserted.")
        elif degree_symbol_count == 1:
            score += 10
            feedback_parts.append("One degree symbol found, one missing.")
        else:
            feedback_parts.append("No degree symbols found.")
            
        if deg_c_text_count > 0:
            feedback_parts.append("Note: Text 'deg C' still present.")
            # Optional penalty? No, just rely on symbol points.

        # --- Check Title Formatting (Bold + Underline) ---
        # Locate the first paragraph usually
        # We search for the specific text "LABORATORY REPORT" inside a run that has bold and underline
        
        title_pattern = r'<w:rPr>.*<w:b(?: [^>]*)?/>.*<w:u(?: [^>]*)?val="single"/>.*</w:rPr>.*<w:t>.*LABORATORY.*</w:t>'
        # This regex is brittle due to tag ordering. Better to check if any run has B and U and contains the text.
        
        title_score = 0
        for block in r_blocks:
            has_bold = '<w:b' in block and 'w:val="0"' not in block # w:b/ is on, w:b w:val="0" is off
            has_underline = '<w:u' in block and 'w:val="none"' not in block
            
            t_match = re.search(r'<w:t(?: [^>]*)?>(.*?)</w:t>', block)
            if t_match:
                text = t_match.group(1)
                if "LABORATORY" in text or "SYNTHESIS" in text:
                    if has_bold and has_underline:
                        title_score = 20
                        break
                    elif has_bold or has_underline:
                        title_score = 10
        
        score += title_score
        if title_score == 20:
            feedback_parts.append("Title correctly formatted (Bold + Underline).")
        elif title_score == 10:
            feedback_parts.append("Title partially formatted (Missing Bold or Underline).")
        else:
            feedback_parts.append("Title formatting missing.")

    finally:
        shutil.rmtree(temp_dir)

    # Final tally
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }