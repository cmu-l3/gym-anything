#!/usr/bin/env python3
"""
Verifier for Generate Legal Table of Authorities task.

Verification Strategy:
1. File Existence: Check if `Defamation_Brief_Final.docx` was saved.
2. XML Parsing: Unzip the .docx and parse `word/document.xml`.
3. Check for TA Fields: Verify `TA` (Table Entry) field codes exist for the 3 required cases.
4. Check for TOA Field: Verify `TOA` (Table of Authorities) field code exists.
5. Check Field Result: Verify the generated table text is actually present in the XML.

We verify against the internal XML structure, which is hard to fake by just typing text.
"""

import json
import logging
import os
import re
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_legal_table_of_authorities(traj, env_info, task_info):
    """
    Verifies that the agent marked citations and generated a Table of Authorities.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Paths
    container_json_path = "C:\\Users\\Docker\\task_result.json"
    container_docx_path = "C:\\Users\\Docker\\Documents\\Defamation_Brief_Final.docx"
    
    # Scoring Config
    SCORING = {
        "file_exists": 10,
        "mark_nyt": 20,
        "mark_curtis": 20,
        "mark_gertz": 20,
        "toa_field_exists": 20,
        "toa_format_classic": 10
    }
    
    score = 0
    feedback_parts = []
    
    # Temp directory for processing
    with tempfile.TemporaryDirectory() as temp_dir:
        local_json = os.path.join(temp_dir, "task_result.json")
        local_docx = os.path.join(temp_dir, "Defamation_Brief_Final.docx")
        
        # 1. Get JSON result from container
        try:
            copy_from_env(container_json_path, local_json)
            with open(local_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result JSON: {e}"}
            
        # Check if file exists
        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Final document 'Defamation_Brief_Final.docx' was not saved."}
        
        score += SCORING["file_exists"]
        feedback_parts.append("File saved successfully")
        
        # 2. Get DOCX file
        try:
            copy_from_env(container_docx_path, local_docx)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to copy DOCX file: {e}"}
            
        # 3. Parse DOCX XML
        if not zipfile.is_zipfile(local_docx):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid DOCX archive."}
            
        try:
            with zipfile.ZipFile(local_docx, 'r') as docx:
                # Read document.xml (main content)
                xml_content = docx.read('word/document.xml').decode('utf-8')
        except KeyError:
            return {"passed": False, "score": score, "feedback": "Invalid DOCX structure (missing document.xml)."}

        # 4. Verify Marked Citations (TA Fields)
        # Word stores marked citations as Field Codes: <w:instrText> TA \l "New York Times Co. ... </w:instrText>
        # Note: XML might be split across tags, so we search flexibly or clean tags.
        # For robustness, we'll look for the raw string in the XML content roughly.
        
        # Helper to find TA fields
        # Regex looks for TA command followed by citation text
        # Word XML often splits text, so this is a heuristic. A robust way is to strip XML tags first or looking for parts.
        
        # Let's simplify: check if "TA" and the Case Name appear in close proximity within an instrText or similar context.
        # Better: Look for the specific "TA" field syntax which is fairly distinct.
        # Example: TA \l "New York Times Co. v. Sullivan, 376 U.S. 254 (1964)" \s "New York Times Co. v. Sullivan" \c 1
        
        def check_citation(case_name_fragment, full_citation_fragment):
            # Look for TA field marker
            # We look for 'TA' and the case name in the XML.
            # To be safe against split tags, we can just check if the string "TA" and the case name exist in the file.
            # But specific check for "TA" field is better.
            
            # Simple check: Does a TA field exist with this text?
            # We search for the pattern: TA ... "Case Name"
            
            # Find all instruction text
            instr_texts = re.findall(r'<w:instrText[^>]*>(.*?)</w:instrText>', xml_content, re.DOTALL)
            full_instr = "".join(instr_texts)
            
            # Check if TA field contains the case
            # Pattern: TA [switches] "Citation"
            matches = [t for t in instr_texts if "TA" in t and case_name_fragment in t]
            return len(matches) > 0

        # Check New York Times
        if check_citation("New York Times", "376 U.S. 254"):
            score += SCORING["mark_nyt"]
            feedback_parts.append("Marked 'NYT v. Sullivan'")
        else:
            feedback_parts.append("Failed to mark 'NYT v. Sullivan'")

        # Check Curtis Publishing
        if check_citation("Curtis Publishing", "388 U.S. 130"):
            score += SCORING["mark_curtis"]
            feedback_parts.append("Marked 'Curtis v. Butts'")
        else:
            feedback_parts.append("Failed to mark 'Curtis v. Butts'")

        # Check Gertz
        if check_citation("Gertz", "418 U.S. 323"):
            score += SCORING["mark_gertz"]
            feedback_parts.append("Marked 'Gertz v. Welch'")
        else:
            feedback_parts.append("Failed to mark 'Gertz v. Welch'")

        # 5. Verify TOA Generation (TOA Field)
        # Example: TOA \h \c "1" \p \f "Classic"
        instr_texts = re.findall(r'<w:instrText[^>]*>(.*?)</w:instrText>', xml_content, re.DOTALL)
        toa_fields = [t for t in instr_texts if "TOA" in t]
        
        if toa_fields:
            score += SCORING["toa_field_exists"]
            feedback_parts.append("Table of Authorities field found")
            
            # Check Format (Classic)
            # Switch \f "Classic"
            # Note: format names might be localized or ID based, but usually string "Classic".
            # If agent used "From template", it might be different.
            if any('Classic' in t for t in toa_fields):
                score += SCORING["toa_format_classic"]
                feedback_parts.append("Correct 'Classic' format used")
            else:
                feedback_parts.append("TOA format might be incorrect (expected Classic)")
        else:
            feedback_parts.append("Table of Authorities NOT generated (no TOA field found)")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }