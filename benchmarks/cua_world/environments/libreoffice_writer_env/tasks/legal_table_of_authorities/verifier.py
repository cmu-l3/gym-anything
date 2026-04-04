#!/usr/bin/env python3
"""
Verifier for legal_table_of_authorities task.
Checks for the existence of TOA fields and correct content in the output document.
"""

import json
import os
import tempfile
import logging
import re
from zipfile import ZipFile
from lxml import etree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_table_of_authorities(traj, env_info, task_info):
    """
    Verify the Table of Authorities task.
    
    Criteria:
    1. Output file exists and was created during task.
    2. XML contains 'TOA' field instruction (Table generated).
    3. XML contains 'TA' field instructions (Entries marked).
    4. Specific citations (Cases/Statutes) are present in the marked entries.
    5. Categories 'Cases' and 'Statutes' are present in the document text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cases = metadata.get('expected_cases', ["Hadley v. Baxendale", "Hawkins v. McGee"])
    expected_statutes = metadata.get('expected_statutes', ["U.C.C. § 2-715", "28 U.S.C. § 1332"])
    
    # Load basic result info
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_json.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Copy the DOCX file for deep inspection
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env("/home/ga/Documents/appellate_brief_final.docx", temp_docx.name)
        
        # Analyze DOCX XML directly to find fields
        # LibreOffice Writer TOA fields often look like: 
        # <w:instrText> TOA \h \c "1" \p </w:instrText>
        # <w:instrText> TA \l "Hadley v. Baxendale" \s "Hadley" \c 1 </w:instrText>
        
        toa_field_found = False
        ta_fields_found = 0
        marked_entries = []
        document_text = ""
        
        with ZipFile(temp_docx.name, 'r') as z:
            xml_content = z.read('word/document.xml')
            root = etree.fromstring(xml_content)
            
            # Namespace map for XPath
            ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
            
            # Check for Field Instructions
            instr_texts = root.findall('.//w:instrText', ns)
            for instr in instr_texts:
                text = instr.text or ""
                if 'TOA' in text:
                    toa_field_found = True
                if 'TA ' in text and '\\l' in text:
                    ta_fields_found += 1
                    # Extract the cited name roughly
                    match = re.search(r'\\l "([^"]+)"', text)
                    if match:
                        marked_entries.append(match.group(1))
                    else:
                        marked_entries.append(text) # Fallback

            # Extract full text for category check
            texts = root.findall('.//w:t', ns)
            document_text = " ".join([t.text for t in texts if t.text])

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse DOCX: {e}"}
    finally:
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)

    # Scoring
    score = 0
    feedback = []

    # 1. File exists (10 pts)
    score += 10
    feedback.append("File exists.")

    # 2. Table Generated (20 pts)
    if toa_field_found:
        score += 20
        feedback.append("Table of Authorities field detected.")
    else:
        # Fallback: Check if there's a visual table with leaders if field code is hidden/converted
        # Simple heuristic: Look for "Cases" and "Statutes" headers followed by entries
        if "Cases" in document_text and "Statutes" in document_text:
             # Partial credit if field missing but text looks right
            score += 10
            feedback.append("TOA field not found, but category headers present.")
        else:
            feedback.append("Table of Authorities field NOT detected.")

    # 3. Entries Marked (TA fields) (20 pts)
    # We expect at least 4 marked entries (2 cases + 2 statutes)
    if ta_fields_found >= 4:
        score += 20
        feedback.append(f"Found {ta_fields_found} marked citations (TA fields).")
    elif ta_fields_found > 0:
        score += 10
        feedback.append(f"Found only {ta_fields_found} marked citations (expected 4+).")
    else:
        feedback.append("No marked citation (TA) fields found.")

    # 4. Check specific content marked (30 pts)
    found_cases = 0
    found_statutes = 0
    
    # Check marked entries (from XML fields) OR document text (if generated)
    # Combining sources to be robust
    combined_content = " ".join(marked_entries) + " " + document_text
    
    for case in expected_cases:
        # Check for case name
        if case in combined_content:
            found_cases += 1
    
    for stat in expected_statutes:
        # Check for statute
        if stat in combined_content:
            found_statutes += 1

    score += (found_cases / len(expected_cases)) * 15
    score += (found_statutes / len(expected_statutes)) * 15
    
    feedback.append(f"Cases identified: {found_cases}/{len(expected_cases)}.")
    feedback.append(f"Statutes identified: {found_statutes}/{len(expected_statutes)}.")

    # 5. Categories Correct (20 pts)
    # Check if "Cases" and "Statutes" appear as headings in the doc
    cats_found = 0
    if "Cases" in document_text: cats_found += 1
    if "Statutes" in document_text: cats_found += 1
    
    if cats_found == 2:
        score += 20
        feedback.append("Both 'Cases' and 'Statutes' categories found.")
    elif cats_found == 1:
        score += 10
        feedback.append("One category heading found.")
    else:
        feedback.append("Category headings missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }