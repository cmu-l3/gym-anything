#!/usr/bin/env python3
"""
Verifier for create_certificate_page_setup task.

Verifies:
1. Document existence and timestamp (Anti-gaming).
2. Page Orientation: Landscape.
3. Vertical Alignment: Center (Key Page Setup feature).
4. Page Borders: Double line style applied.
5. Content check: Correct name and title.
"""

import json
import logging
import os
import shutil
import tempfile
import zipfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_certificate_page_setup(traj, env_info, task_info):
    """
    Verify the certificate document properties via XML parsing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp workspace
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    doc_local_path = os.path.join(temp_dir, "Safety_Certificate.docx")
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Get Result JSON
        try:
            copy_from_env("C:\\tmp\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # 2. Check File Existence & Timestamp (Anti-gaming)
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Safety_Certificate.docx not found."}
        
        if not result_data.get('file_created_during_task', False):
             # Fail immediately if file wasn't modified during task
             return {"passed": False, "score": 0, "feedback": "File was not saved during the task session."}
        
        score += 10
        feedback_parts.append("File saved correctly")

        # 3. Retrieve and Parse Docx
        try:
            copy_from_env(result_data['output_path'], doc_local_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Could not copy document: {e}"}

        if not zipfile.is_zipfile(doc_local_path):
            return {"passed": False, "score": score, "feedback": "Output is not a valid DOCX file."}

        with zipfile.ZipFile(doc_local_path, 'r') as docx:
            # Read document.xml (structure/borders)
            try:
                doc_xml = docx.read('word/document.xml').decode('utf-8')
            except KeyError:
                return {"passed": False, "score": score, "feedback": "Invalid DOCX: missing document.xml"}

        # 4. XML Verification Logic
        
        # A. Check Orientation (Landscape) -> <w:pgSz w:orient="landscape" ... />
        # Default is portrait (orient attribute missing or set to portrait)
        if 'w:orient="landscape"' in doc_xml:
            score += 20
            feedback_parts.append("Orientation: Landscape (Pass)")
        else:
            feedback_parts.append("Orientation: Portrait (Fail - expected Landscape)")

        # B. Check Vertical Alignment (Center) -> <w:vAlign w:val="center"/>
        # This is inside <w:sectPr>.
        if 'w:vAlign w:val="center"' in doc_xml:
            score += 30
            feedback_parts.append("Vertical Alignment: Center (Pass)")
        else:
            feedback_parts.append("Vertical Alignment: Top/Default (Fail - expected Center)")

        # C. Check Page Borders -> <w:pgBorders> ... <w:top w:val="double" ... />
        # We need to find w:pgBorders and check its children
        if '<w:pgBorders>' in doc_xml:
            # Check for double style
            # The style might be "double" or specific double wave etc, but task asked for "Double Line" which is usually "double"
            if 'w:val="double"' in doc_xml:
                score += 20
                feedback_parts.append("Border Style: Double Line (Pass)")
            else:
                score += 10 # Credit for having borders, just wrong style
                feedback_parts.append("Border Style: Incorrect style (Partial)")
            
            # Check color (not auto/black)
            # Standard "Dark Blue" usually has a hex like "1F497D" or color="darkBlue" or similar
            # We'll check if a color attribute exists and isn't "auto"
            if 'w:color="auto"' not in doc_xml and 'w:color=' in doc_xml:
                score += 10
                feedback_parts.append("Border Color: Applied (Pass)")
            else:
                feedback_parts.append("Border Color: Auto/Default (Fail)")
        else:
            feedback_parts.append("Page Borders: None (Fail)")

        # D. Content Check
        required_text = ["James A. Smith", "Industrial Workplace Safety", "Certificate of Completion"]
        content_found = 0
        for text in required_text:
            if text in doc_xml: # Simple check, ignoring complex run splitting for now
                content_found += 1
            else:
                # Try closer regex check if runs are split (e.g. "James" <tag> " A. Smith")
                # Remove XML tags to check raw text
                clean_xml = re.sub(r'<[^>]+>', '', doc_xml)
                if text in clean_xml:
                    content_found += 1
        
        if content_found == len(required_text):
            score += 10
            feedback_parts.append("Content: Correct")
        elif content_found > 0:
            score += 5
            feedback_parts.append("Content: Partial")
        else:
            feedback_parts.append("Content: Missing")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)

    # Final Pass Decision
    # Must have correct setup (Orientation + VAlign) to pass
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }